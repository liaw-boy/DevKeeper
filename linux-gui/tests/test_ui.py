import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QThreadPool
from PySide6.QtWidgets import QApplication

from devkeeper_gui import cli
from devkeeper_gui.app import MainWindow


def test_window_shows_incomplete_audit_banner(tmp_path, monkeypatch):
    fake = tmp_path / "devkeeper-cli"
    fake.write_text("#!/bin/sh\nexit 9\n")
    fake.chmod(0o755)
    monkeypatch.setenv(cli.CLI_ENV, str(fake))  # never run the real CLI or reach OSV from tests
    app = QApplication.instance() or QApplication([])
    win = MainWindow.__new__(MainWindow)
    MainWindow.__init__(win, app)
    win._pending = 1
    win._on_audit(cli.Audit(items=[{"package": "p", "severity": "high", "currentVersion": "1",
                                    "safeVersion": None, "environments": ["e"], "cves": []}], incomplete=True))
    assert win.audit_table.rowCount() == 1
    assert win.audit_banner.isHidden() is False
    assert win.cards["vuln"].text() == "1＋"
    app.processEvents()
    QThreadPool.globalInstance().waitForDone(60000)
    app.processEvents()
