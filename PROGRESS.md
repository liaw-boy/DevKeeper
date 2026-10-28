# 改版進度交接（暫時文件，改版完成後刪除）

分支：`overhaul`（已推送，尚未合併到 `main`）。設計規格見 `DESIGN.md`，專案規則見 `AGENTS.md`，相關專案整理見 `docs/RELATED_PROJECTS.md`。

## 已完成

- DK 設計系統（`Sources/DevKeeper/Design/`）與元件展示頁；側邊欄、選單列面板、總覽、npm、Python、Homebrew、資料庫、AI 工具、執行日誌、安全弱點、設定、詳細頁、安裝面板、批次修復確認，全部改用 DK 元件。舊 `Theme.swift` 已刪除。
- 淺色、深色、跟隨系統三種外觀（設定頁），主視窗與選單列面板都會跟著切。
- 選單列圖示是紙箱色立體箱子，開啟面板時蓋子打開。App 圖示是強調藍底加 `shippingbox.fill`。
- 稽核可信度：OSV 查詢失敗不再被當成「沒有弱點」（`AuditOutcome`、`AuditState`，CLI 結束代碼 3，CI 接受 0、1、3）。
- 會改系統的操作（升級、安裝、移除、修復）一律先在確認面板列出實際指令。
- Homebrew 預設隱藏只因相依才裝的套件；Python 與 npm 的說明、專案連結從 PyPI／npm registry 取得（Python 有本機快取）。
- 資料庫頁不再替內嵌資料庫（sqlite）顯示「啟動」；總覽的執行環境區標示 Node、npm、Python 的來源與是否有新版。
- uv 工具管理（Python 頁的「pip 套件／uv 工具」切換）：列出、更新、移除、安裝；用 `==` 釘選的工具顯示「已釘選」不給更新；更新後重讀版本並跑 `uv pip check`；側邊欄、總覽、選單列的數量都含 uv 工具。工具名稱用嚴格 PyPI 名稱規則（`UVToolService.strictName`）。

- Linux 版（`linux-gui/`，Python + PySide6，唯讀）：總覽、Python、npm、pip、uv 工具、安全稽核；資料來自 `devkeeper-cli --json`（`scan` 新增 `uvStatus`、`uvTools`），稽核結束代碼 3 顯示「結果不完整」。CI 的 `Linux GUI` 工作跑 pytest、用 PyInstaller + appimagetool 打成 `DevKeeper-x86_64.AppImage`，並用 `--check` 啟動煙霧測試（成品在 Actions 的 artifact，尚未附到 release）。
- Linux 發版 CLI 改在 Ubuntu 22.04（`swift:6.0-jammy`）編，glibc 2.35 以上能跑；先前在 noble 編的需要 glibc 2.38。**已發布的 v1.3.0 的 Linux CLI 仍是舊的，在 22.04 跑不起來。**

## 尚未驗證（需要人操作）

- Linux 圖形版只在 macOS 離屏與 CI 離屏跑過，沒有人在真的 Linux 桌面開過；沒有點擊測試；樣式只是 DK 配色的仿製，不是 DK 元件。AppImage 的 xcb 函式庫有補裝但未逐一確認。（需要人操作）

- uv 工具的更新、移除、安裝尚未在真實工具上端到端執行（未獲同意動使用者的工具）；釘選顯示只有單元測試；沒網路時的行為未測。
- 所有點擊行為：確認面板、下拉、篩選、分段切換、啟停服務、Esc、點背景關閉。
- 總覽最下方的執行環境區，與安全頁有弱點時的卡片、確認面板、批次修復面板（截圖工具無法捲動或製造弱點）。
- 選單列面板的動畫與實際大小（只用大圖預覽與面板區域截圖看過）。

## 尚未做

0. Linux：把 AppImage 附到 release（要發新版並打 tag，需明確同意）、`--screenshot` 讓 CI 截 Linux 畫面、自動更新、ARM 版、可操作的版本（更新／移除）、CI 檢查 CLI JSON 欄位改動時 Linux 版測試一併失敗、本機網頁介面沒有 uv 頁、AppImage 打包用的 appimagetool 沒有驗證雜湊。

1. Python 頁沒有「全部更新」，uv 工具也沒有（相依衝突風險，只能逐一更新）（需要在 Core 新增批次升級邏輯與測試）。
2. B 區塊：新版本／新弱點的系統通知、視窗關閉後可從選單列重開（需 AppDelegate，單一 `Window` scene 關閉會結束 App）、釘選與略過版本、歷史紀錄頁、勾選後批次升級。
3. 稽核頁的其他舊問題：CLI `--json` 輸出不含 `failedLookups`（stderr 才有警告）；移除指令在顯示與執行處各有一份，可能分岔，之後可改成服務直接用 `PackageItem.uninstallCommands`。
4. 使用者環境的相依衝突未還原（未獲同意）：`uv tool` 的 demo-agent、demo-app 為 filelock 4.2.4（要求 <4），demo-tool 為 libbaz 4.1.3（要求 <4）。建議用 `uv pip install --python <tool python> "filelock<4"` 這類範圍指令，之後重跑 `uv pip check` 與稽核。
5. 發版：版本號在 `bundle.sh`，打 tag 與發布要等明確同意。

## 驗證方式

- 完成標準：`swift build`（無警告）、`swift test`（目前 61 個；`linux-gui` 的 pytest 16 個）、`./bundle.sh` 與 `codesign --verify --deep --strict DevKeeper.app`、`open -n DevKeeper.app` 後 20 秒內無崩潰報告。
- 元件展示頁：`DEVKEEPER_GALLERY=1 .build/debug/DevKeeper`；`DEVKEEPER_GALLERY_SHOW=dropdown|tooltip|longtip|confirm|longmodal|modaldropdown` 直接打開浮層。
- 開發輔助環境變數：`DEVKEEPER_TAB=<頁面中文名>` 直接開某頁、`DEVKEEPER_OPEN=install|detail` 開啟面板、`DEVKEEPER_SHOW_MENU_PANEL=1` 啟動後打開選單列面板。
- 截圖只截 DevKeeper 視窗：用 `CGWindowListCopyWindowInfo` 依 PID 找視窗編號，再 `screencapture -l <id> -o -x 檔案`；選單列面板用它自己的區域（`-R`）。不要全螢幕截圖。
- **不要模擬滑鼠或鍵盤事件**：曾因視窗被其他程式蓋住，點擊落到使用者的瀏覽器。
