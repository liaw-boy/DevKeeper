"""Read-only DevKeeper window: overview, Python, npm, pip and security audit."""
from __future__ import annotations

import sys
from typing import Callable, List, Optional

from PySide6.QtCore import QObject, QRunnable, QThreadPool, Qt, Signal
from PySide6.QtGui import QColor
from PySide6.QtWidgets import (QAbstractItemView, QApplication, QFrame, QHBoxLayout, QHeaderView, QLabel,
                               QLineEdit, QListWidget, QMainWindow, QPushButton, QStackedWidget,
                               QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget)

from . import cli, theme

PAGES = ["總覽", "Python", "npm", "pip", "安全稽核"]


class _Signals(QObject):
    done = Signal(object)
    failed = Signal(str)


class _Job(QRunnable):
    """Runs a blocking CLI call off the UI thread."""

    def __init__(self, fn: Callable):
        super().__init__()
        self.fn = fn
        self.signals = _Signals()
        self.setAutoDelete(False)  # the window owns the job, so its signals outlive run()

    def run(self):
        try:
            self.signals.done.emit(self.fn())
        except cli.CLIError as exc:
            self.signals.failed.emit(str(exc))
        except Exception:  # never leak internals into the UI
            self.signals.failed.emit("讀取時發生未預期的錯誤。")


def _is_dark(app: QApplication) -> bool:
    return app.styleHints().colorScheme() == Qt.ColorScheme.Dark


def _table(headers: List[str]) -> QTableWidget:
    t = QTableWidget(0, len(headers))
    t.setHorizontalHeaderLabels(headers)
    t.verticalHeader().setVisible(False)
    t.setEditTriggers(QAbstractItemView.NoEditTriggers)
    t.setSelectionBehavior(QAbstractItemView.SelectRows)
    t.setAlternatingRowColors(True)
    t.setShowGrid(False)
    h = t.horizontalHeader()
    h.setSectionResizeMode(QHeaderView.ResizeToContents)
    h.setStretchLastSection(True)
    h.setDefaultAlignment(Qt.AlignLeft | Qt.AlignVCenter)
    return t


def _fill(table: QTableWidget, rows: List[List[str]], colors: Optional[List[Optional[str]]] = None):
    table.setRowCount(len(rows))
    for r, row in enumerate(rows):
        for c, text in enumerate(row):
            item = QTableWidgetItem(text)
            if colors and colors[r] and c == 0:
                item.setForeground(QColor(colors[r]))
            table.setItem(r, c, item)


def _page(title: str, subtitle: str):
    box = QWidget()
    lay = QVBoxLayout(box)
    lay.setContentsMargins(24, 20, 24, 20)
    lay.setSpacing(12)
    head = QLabel(title)
    head.setObjectName("title")
    sub = QLabel(subtitle)
    sub.setObjectName("subtitle")
    sub.setWordWrap(True)
    for label in (head, sub):
        label.setTextFormat(Qt.PlainText)  # text can come from the CLI; never parse it as rich text
    lay.addWidget(head)
    lay.addWidget(sub)
    return box, lay


def _card(label: str):
    f = QFrame()
    f.setObjectName("card")
    lay = QVBoxLayout(f)
    lay.setContentsMargins(16, 12, 16, 12)
    value = QLabel("—")
    value.setObjectName("cardValue")
    cap = QLabel(label)
    cap.setObjectName("muted")
    lay.addWidget(value)
    lay.addWidget(cap)
    return f, value


class MainWindow(QMainWindow):
    def __init__(self, app: QApplication):
        super().__init__()
        self.app = app
        self.pool = QThreadPool.globalInstance()
        self.scan: Optional[cli.Scan] = None
        self._jobs: set = set()
        self.setWindowTitle("DevKeeper")
        self.resize(1000, 680)

        root = QWidget()
        outer = QHBoxLayout(root)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)
        self.setCentralWidget(root)

        side = QWidget()
        side.setObjectName("sidebar")
        side.setFixedWidth(190)
        sl = QVBoxLayout(side)
        sl.setContentsMargins(0, 0, 0, 12)
        brand = QLabel("DevKeeper")
        brand.setObjectName("brand")
        self.nav = QListWidget()
        self.nav.addItems(PAGES)
        self.refresh_btn = QPushButton("重新整理")
        self.refresh_btn.clicked.connect(self.reload)
        sl.addWidget(brand)
        sl.addWidget(self.nav, 1)
        sl.addWidget(self.refresh_btn)
        sl.setAlignment(self.refresh_btn, Qt.AlignHCenter)
        outer.addWidget(side)

        self.stack = QStackedWidget()
        outer.addWidget(self.stack, 1)
        self._build_overview()
        self._build_python()
        self._build_packages("npm", "npm 全域套件", "有新版的 npm 全域套件")
        self._build_packages("pip", "pip 套件", "目前使用的 Python 直譯器上有新版的套件")
        self._build_audit()
        self.nav.currentRowChanged.connect(self.stack.setCurrentIndex)
        self.nav.setCurrentRow(0)
        self.reload()

    def closeEvent(self, event):
        self.pool.clear()
        super().closeEvent(event)

    # ----- pages -----
    def _build_overview(self):
        page, lay = _page("總覽", "")
        self.overview_sub = page.findChild(QLabel, "subtitle")
        row = QHBoxLayout()
        self.cards = {}
        for key, label in [("npm", "npm 待更新"), ("pip", "pip 待更新"), ("sys", "系統套件待更新"), ("vuln", "已知弱點")]:
            card, value = _card(label)
            self.cards[key] = value
            row.addWidget(card)
        lay.addLayout(row)
        self.overview_error = QLabel("")
        self.overview_error.setObjectName("banner")
        self.overview_error.hide()
        lay.addWidget(self.overview_error)
        lay.addStretch(1)
        self.stack.addWidget(page)

    def _build_python(self):
        page, lay = _page("Python", "偵測到的 Python 直譯器與支援狀態")
        self.py_table = _table(["版本", "來源", "支援狀態", "路徑"])
        lay.addWidget(self.py_table, 1)
        self.stack.addWidget(page)

    def _build_packages(self, kind: str, title: str, subtitle: str):
        page, lay = _page(title, subtitle)
        search = QLineEdit()
        search.setPlaceholderText("搜尋套件名稱")
        table = _table(["套件", "可更新到"])
        search.textChanged.connect(lambda text, t=table: self._filter(t, text))
        lay.addWidget(search)
        lay.addWidget(table, 1)
        setattr(self, f"{kind}_table", table)
        setattr(self, f"{kind}_sub", page.findChild(QLabel, "subtitle"))
        self.stack.addWidget(page)

    def _build_audit(self):
        page, lay = _page("安全稽核", "以 OSV 查詢已安裝套件的已知弱點；這裡只檢視，修復請用 devkeeper-cli fix")
        self.audit_banner = QLabel("")
        self.audit_banner.setObjectName("banner")
        self.audit_banner.hide()
        self.audit_table = _table(["嚴重度", "套件", "目前版本", "安全版本", "環境", "編號"])
        lay.addWidget(self.audit_banner)
        lay.addWidget(self.audit_table, 1)
        self.stack.addWidget(page)

    @staticmethod
    def _filter(table: QTableWidget, text: str):
        needle = text.strip().lower()
        for r in range(table.rowCount()):
            item = table.item(r, 0)
            table.setRowHidden(r, bool(needle) and needle not in item.text().lower())

    # ----- data -----
    def reload(self):
        if self._jobs:
            return
        self.refresh_btn.setEnabled(False)
        self.refresh_btn.setText("讀取中…")
        self._pending = 3
        self._run(cli.load_scan, self._on_scan)
        self._run(cli.load_interpreters, self._on_interpreters)
        self._run(cli.load_audit, self._on_audit)

    def _run(self, fn, ok):
        job = _Job(fn)
        self._jobs.add(job)
        job.signals.done.connect(lambda result, j=job: (self._jobs.discard(j), ok(result)))
        job.signals.failed.connect(lambda msg, f=fn, j=job: (self._jobs.discard(j), self._on_error(f, msg)))
        self.pool.start(job)

    def _finish_one(self):
        self._pending -= 1
        if self._pending <= 0:
            self.refresh_btn.setEnabled(True)
            self.refresh_btn.setText("重新整理")

    def _on_error(self, fn, message: str):
        self.overview_error.setText(message)
        self.overview_error.show()
        if fn is cli.load_audit:
            self.audit_banner.setText(message)
            self.audit_banner.show()
        self._finish_one()

    def _on_scan(self, scan: cli.Scan):
        self.scan = scan
        self.overview_error.hide()
        self.overview_sub.setText(scan.os)
        self.cards["npm"].setText(str(len(scan.npm_outdated)))
        self.cards["pip"].setText(str(len(scan.pip_outdated)))
        self.cards["sys"].setText(str(len(scan.system_upgradable)))
        for kind, count, outdated in (("npm", scan.npm_count, scan.npm_outdated), ("pip", scan.pip_count, scan.pip_outdated)):
            getattr(self, f"{kind}_sub").setText(f"共 {count} 個，{len(outdated)} 個有新版")
            _fill(getattr(self, f"{kind}_table"), [[n, v] for n, v in sorted(outdated.items())])
        self._finish_one()

    def _on_interpreters(self, items: List[dict]):
        labels = {"supported": "支援中", "endingSoon": "即將結束支援", "endOfLife": "已結束支援"}
        rows = [[str(i.get("version", "")), str(i.get("source", "")),
                 f"{labels.get(str(i.get('supportStatus')), '未知')}（至 {i.get('supportUntil', '?')}）"
                 + ("，唯讀" if i.get("externallyManaged") else ""), str(i.get("path", ""))] for i in items]
        _fill(self.py_table, rows)
        self._finish_one()

    def _on_audit(self, audit: cli.Audit):
        dark = _is_dark(self.app)
        rows, colors = [], []
        for i in audit.items:
            rows.append([str(i.get("severity", "")), str(i.get("package", "")), str(i.get("currentVersion", "")),
                         str(i.get("safeVersion") or "—"), "、".join(map(str, i.get("environments", []))),
                         "、".join(map(str, i.get("cves", [])))])
            colors.append(theme.severity_color(str(i.get("severity", "")), dark))
        _fill(self.audit_table, rows, colors)
        self.cards["vuln"].setText(str(len(audit.items)) + ("＋" if audit.incomplete else ""))
        if audit.incomplete:
            self.audit_banner.setText("部分套件查詢失敗，結果不完整；沒有列出的不代表沒有弱點。請檢查網路後重新整理。")
            self.audit_banner.show()
        else:
            self.audit_banner.hide()
        self._finish_one()


def _self_check(app: QApplication, win: MainWindow) -> int:
    """`--check`: load everything once without showing a window and report whether the CLI answered.
    Used by CI to prove the packaged build starts; exit 0 only when no page reported an error."""
    QThreadPool.globalInstance().waitForDone(300000)
    app.processEvents()
    failed = not win.overview_error.isHidden()
    print("devkeeper-gui check:", "FAILED - " + win.overview_error.text() if failed else "ok")
    return 1 if failed else 0


def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName("DevKeeper")
    win = MainWindow(app)
    if "--check" in sys.argv:
        return _self_check(app, win)
    app.setStyleSheet(theme.stylesheet(_is_dark(app)))
    app.styleHints().colorSchemeChanged.connect(lambda *_: app.setStyleSheet(theme.stylesheet(_is_dark(app))))
    win.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
