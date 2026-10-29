# devkeeper-gui

DevKeeper 的 Python 桌面版（PySide6），唯讀檢視：總覽、Python 直譯器、npm、pip、安全稽核。
資料全部來自 `devkeeper-cli --json`，這個程式本身不執行任何更新、移除或修復。

## 使用

```bash
# 先備妥 devkeeper-cli（在專案根目錄：swift build -c release --product devkeeper-cli），放進 PATH，
# 或用環境變數指定：export DEVKEEPER_CLI=/path/to/devkeeper-cli
pip install .            # 需要 Python 3.9 以上
devkeeper-gui
```

稽核若有部分套件查詢失敗（CLI 結束代碼 3），畫面會標示「結果不完整」，不會當成沒有弱點。

## 測試

```bash
pip install -e ".[test]"
DEVKEEPER_CLI=/path/to/devkeeper-cli pytest   # 介面測試用 Qt offscreen 模式，不需要桌面
```

## 安全

- 這個程式唯一會執行的外部程式是 `devkeeper-cli`（`DEVKEEPER_CLI` 指定的路徑，否則取 PATH 上第一個）。能改這個環境變數或 PATH 可寫目錄的人，就能決定它執行什麼，請確保這些位置只有你能寫入。
- 以參數列表呼叫（不經 shell）、有逾時與輸出大小上限；CLI 的輸出會驗證型別，並以純文字顯示。
