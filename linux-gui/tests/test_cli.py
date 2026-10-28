import json
import os
import stat

import pytest

from devkeeper_gui import cli


def fake_cli(tmp_path, body: str, monkeypatch):
    path = tmp_path / "devkeeper-cli"
    path.write_text("#!/bin/sh\n" + body)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    monkeypatch.setenv(cli.CLI_ENV, str(path))


def test_missing_cli(monkeypatch):
    monkeypatch.setenv(cli.CLI_ENV, "/nonexistent/devkeeper-cli")
    with pytest.raises(cli.CLIError):
        cli.run_json(["scan"])


def test_bad_json(tmp_path, monkeypatch):
    fake_cli(tmp_path, "echo not-json\n", monkeypatch)
    with pytest.raises(cli.CLIError):
        cli.run_json(["scan"])


def test_unexpected_exit_code(tmp_path, monkeypatch):
    fake_cli(tmp_path, "echo '{}'; exit 2\n", monkeypatch)
    with pytest.raises(cli.CLIError):
        cli.run_json(["scan"])


def test_timeout(tmp_path, monkeypatch):
    fake_cli(tmp_path, "sleep 5\n", monkeypatch)
    with pytest.raises(cli.CLIError):
        cli.run_json(["scan"], timeout=1)


def test_arguments_are_not_shell_interpreted(tmp_path, monkeypatch):
    marker = tmp_path / "pwned"
    fake_cli(tmp_path, 'echo "[]"\n', monkeypatch)
    cli.run_json(["audit", f"; touch {marker}"])
    assert not marker.exists()


def test_scan_rejects_wrong_types():
    with pytest.raises(cli.CLIError):
        cli.parse_scan({"npmGlobalCount": "abc"})
    with pytest.raises(cli.CLIError):
        cli.parse_scan({"pipCount": None})


def test_audit_lists_are_normalised():
    audit = cli.parse_audit([{"severity": "low", "environments": "abc", "cves": {"k": 1}}], 0)
    assert audit.items[0]["environments"] == [] and audit.items[0]["cves"] == []


def test_output_size_limit(tmp_path, monkeypatch):
    monkeypatch.setattr(cli, "MAX_OUTPUT", 10)
    fake_cli(tmp_path, 'echo "[                          ]"\n', monkeypatch)
    with pytest.raises(cli.CLIError):
        cli.run_json(["audit"])


def test_audit_exit_3_is_incomplete(tmp_path, monkeypatch):
    fake_cli(tmp_path, "echo '[]'; exit 3\n", monkeypatch)
    audit = cli.load_audit()
    assert audit.incomplete and audit.items == []


def test_audit_exit_1_sorted_by_severity(tmp_path, monkeypatch):
    items = [{"package": "a", "severity": "low"}, {"package": "b", "severity": "critical"}]
    fake_cli(tmp_path, f"echo '{json.dumps(items)}'; exit 1\n", monkeypatch)
    audit = cli.load_audit()
    assert not audit.incomplete
    assert [i["package"] for i in audit.items] == ["b", "a"]


def test_scan_shape_is_validated():
    with pytest.raises(cli.CLIError):
        cli.parse_scan([])
    with pytest.raises(cli.CLIError):
        cli.parse_scan({"npmOutdated": []})
    scan = cli.parse_scan({"os": "Linux", "npmOutdated": {"x": "1"}})
    assert scan.npm_outdated == {"x": "1"} and scan.pip_count == 0


def test_audit_items_must_be_objects():
    with pytest.raises(cli.CLIError):
        cli.parse_audit(["x"], 0)


def test_scan_without_uv_fields_is_still_valid():
    scan = cli.parse_scan({"os": "Linux"})
    assert scan.uv_status == "notInstalled" and scan.uv_tools == []


def test_scan_reads_uv_tools():
    scan = cli.parse_scan({"uvStatus": "ok", "uvTools": [
        {"name": "tool-a", "version": "1.0", "latest": "1.1", "pinned": False},
        {"name": "tool-b", "version": "2.0", "pinned": True}]})
    assert scan.uv_tools[0]["latest"] == "1.1" and scan.uv_tools[1]["latest"] is None
    assert scan.uv_tools[1]["pinned"] is True


def test_scan_rejects_bad_uv_items():
    with pytest.raises(cli.CLIError):
        cli.parse_scan({"uvTools": ["x"]})
