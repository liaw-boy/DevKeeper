"""Thin, read-only wrapper around `devkeeper-cli --json`.

The GUI never builds shell strings: the CLI is started with an argument list and a timeout,
and its output is validated before the interface sees it.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from dataclasses import dataclass, field
from typing import Any, List, Optional

CLI_ENV = "DEVKEEPER_CLI"
DEFAULT_TIMEOUT = 60
TIMEOUTS = {"audit": 300}  # audit queries OSV, which can be slow
MAX_OUTPUT = 8 * 1024 * 1024

# Exit codes that still come with valid JSON. audit: 1 = vulnerabilities found, 3 = lookups failed.
_OK_CODES = {"scan": {0}, "python": {0}, "audit": {0, 1, 3}}


class CLIError(Exception):
    """The CLI could not be run or its answer could not be trusted."""


@dataclass
class Scan:
    os: str
    interpreters: List[dict]
    npm_count: int
    npm_outdated: dict
    pip_python: Optional[str]
    pip_count: int
    pip_outdated: dict
    system_manager: Optional[str]
    system_count: int
    system_upgradable: List[str]
    # "ok", "notInstalled", "failed" or "updatesUnknown"; older CLIs do not report uv at all.
    uv_status: str = "notInstalled"
    uv_tools: List[dict] = field(default_factory=list)


@dataclass
class Audit:
    items: List[dict] = field(default_factory=list)
    # True when the CLI exited with 3: some OSV lookups failed, so a clean result is not trustworthy.
    incomplete: bool = False


def find_cli() -> Optional[str]:
    """The binary that will be executed: DEVKEEPER_CLI or the first devkeeper-cli on PATH, as an absolute real path.

    Whoever controls that variable or a writable PATH entry controls what the GUI runs (see README).
    """
    candidate = os.environ.get(CLI_ENV) or shutil.which("devkeeper-cli")
    if not candidate:
        return None
    path = os.path.realpath(candidate)
    return path if os.path.isfile(path) and os.access(path, os.X_OK) else None


def run_json(args: List[str], timeout: Optional[int] = None) -> tuple:
    """Runs the CLI and returns (exit code, parsed JSON)."""
    cli = find_cli()
    if cli is None:
        raise CLIError(f"找不到 devkeeper-cli。請先安裝，或用環境變數 {CLI_ENV} 指定路徑。")
    timeout = timeout or TIMEOUTS.get(args[0], DEFAULT_TIMEOUT)
    try:
        proc = subprocess.run([cli, *args, "--json"], capture_output=True, text=True,
                              timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        raise CLIError("devkeeper-cli 執行逾時。") from None
    except OSError as exc:
        raise CLIError(f"無法執行 devkeeper-cli：{exc.strerror or exc}") from None
    if proc.returncode not in _OK_CODES.get(args[0], {0}):
        raise CLIError(f"devkeeper-cli 異常結束（結束代碼 {proc.returncode}）。")
    if len(proc.stdout) > MAX_OUTPUT:
        raise CLIError("devkeeper-cli 的輸出過大。")
    try:
        return proc.returncode, json.loads(proc.stdout)
    except json.JSONDecodeError:
        raise CLIError("devkeeper-cli 的輸出不是有效的 JSON。") from None


def _expect(value: Any, kind: type, what: str):
    if not isinstance(value, kind):
        raise CLIError(f"devkeeper-cli 的 {what} 格式不符。")
    return value


def _count(value: Any, what: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise CLIError(f"devkeeper-cli 的 {what} 格式不符。")
    return value


def _strings(value: Any, what: str) -> dict:
    d = _expect(value, dict, what)
    return {str(k): str(v) for k, v in d.items()}


def _text_list(value: Any) -> List[str]:
    return [str(x) for x in value] if isinstance(value, list) else []


def _uv_tool(value: Any) -> dict:
    t = _expect(value, dict, "uvTools item")
    return {"name": str(t.get("name", "")), "version": str(t.get("version", "")),
            "latest": str(t["latest"]) if t.get("latest") else None,
            "pinned": t.get("pinned") is True, "python": str(t["python"]) if t.get("python") else None}


def parse_scan(data: Any) -> Scan:
    d = _expect(data, dict, "scan")
    return Scan(
        os=str(d.get("os", "")),
        interpreters=_expect(d.get("interpreters", []), list, "interpreters"),
        npm_count=_count(d.get("npmGlobalCount", 0), "npmGlobalCount"),
        npm_outdated=_strings(d.get("npmOutdated", {}), "npmOutdated"),
        pip_python=d.get("pipPythonVersion"),
        pip_count=_count(d.get("pipCount", 0), "pipCount"),
        pip_outdated=_strings(d.get("pipOutdated", {}), "pipOutdated"),
        system_manager=d.get("systemPackageManager"),
        system_count=_count(d.get("systemPackageCount", 0), "systemPackageCount"),
        system_upgradable=[str(x) for x in _expect(d.get("systemUpgradable", []), list, "systemUpgradable")],
        uv_status=str(d.get("uvStatus", "notInstalled")),
        uv_tools=[_uv_tool(t) for t in _expect(d.get("uvTools", []), list, "uvTools")],
    )


_SEVERITY_ORDER = {"critical": 0, "high": 1, "moderate": 2, "medium": 2, "low": 3}


def parse_audit(data: Any, exit_code: int) -> Audit:
    items = _expect(data, list, "audit")
    for item in items:
        _expect(item, dict, "audit item")
    for item in items:
        item["environments"] = _text_list(item.get("environments"))
        item["cves"] = _text_list(item.get("cves"))
    items = sorted(items, key=lambda i: _SEVERITY_ORDER.get(str(i.get("severity", "")).lower(), 9))
    return Audit(items=items, incomplete=exit_code == 3)


def parse_interpreters(data: Any) -> List[dict]:
    items = _expect(data, list, "python list")
    for item in items:
        _expect(item, dict, "interpreter")
    return items


def load_scan() -> Scan:
    return parse_scan(run_json(["scan"])[1])


def load_interpreters() -> List[dict]:
    return parse_interpreters(run_json(["python", "list"])[1])


def load_audit() -> Audit:
    code, data = run_json(["audit"])
    return parse_audit(data, code)
