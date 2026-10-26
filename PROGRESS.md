# 改版進度交接（暫時文件，改版完成後刪除）

分支：`overhaul`（`main` 未動、未推送）。設計規格見 `DESIGN.md`，專案規則見 `AGENTS.md`。

## 已完成（皆已提交）

| 提交 | 內容 |
|---|---|
| `5cdcd70`–`348bdd5` | codex 改用 npm `@openai/codex`、aider 用 pipx/uv 升級、拒絕無法執行的 PATH shim；設定頁開關接上功能（掃描頻率、目錄監聽、自身更新、稽核、`SMAppService` 登入啟動）；Intel Homebrew 路徑；詳細頁顯示真實 GitHub release notes（含 `rust-v0.1.0` 這類前綴 tag）；清掉死碼；`AGENTS.md` |
| `7a022f0` | 修復安全化：Python 修復鎖定最低安全版本（`==`）；升級前後跑 `pip check`／`uv pip check`，出現新衝突就自動還原；歷史記在 `~/Library/Application Support/DevKeeper/fix-history.jsonl`；CLI `fix` 不加 `--yes` 只預覽 |
| `6cf3697` | DK 設計系統（`Sources/DevKeeper/Design/`）、`DKOverlayHost`（下拉、提示、對話面板）、元件展示頁、`DESIGN.md` |
| `4a2a885` | 自製側邊欄取代 `NavigationSplitView`；狀態列顯示稽核中；移除 ⌘N 新視窗 |
| `251abea` | 選單列：範本圖示＋數字、去抖動重繪；自製 `MenuBarPanel` 取代 `NSPopover`（點外面、切換程式、Esc 關閉）；Homebrew 全部升級只升清單上的項目（不再是裸 `brew upgrade`） |
| `d46793c`（WIP） | 美化元件：低飽和藍強調色（`DK.accent`）、`DKIconTile`、`DKSourceBadge`（品牌色縮寫，不用官方商標圖）、`DKBar`、`DKSegmentBar`、`DKMetricCard`、卡片淡陰影、`DK.Font.display`（28）、`DKButton(systemImage:)` |

## 下一步（依序）

1. 用 WIP 新元件美化側邊欄（選取用 `accentSubtle`＋強調色圖示、`surfaceSunken` 底色）與選單列面板（圖示方塊、來源標章、比例條、大數字），更新元件展示頁與 `DESIGN.md`（新增：強調色、`display` 字級、來源標章字級例外、按鈕可帶圖示、卡片淡陰影）。使用者已確認：要單色圖示、數據視覺化、大數字卡片、來源標章、柔和質感、低飽和藍。
2. 各頁面改用 DK 元件（目前右側頁面仍是舊樣式）：總覽 → npm/Python/Homebrew/資料庫（共用一個清單元件）→ 安全弱點 → AI 工具 → 執行日誌 → 設定 → 詳細頁、安裝面板（改成 `DKModalPanel`）。每批建置、測試、打包、截圖後提交。
3. 外觀設定（跟隨系統／淺色／深色），移除 `App.swift` 的 `.preferredColorScheme(.dark)` 與 `StatusBarController` 的 `panel.appearance = darkAqua`。舊 `Theme.swift` 在所有頁面遷移後刪除。
4. B 區塊：新版本／新弱點的系統通知、視窗關閉後可從選單列重開（需 AppDelegate，單一 `Window` scene 關閉會結束 App 所以沒用）、釘選與略過、歷史紀錄頁。

## 頁面遷移時要一起修的功能錯誤（UI 審查結果）

- 總覽「全部升級 (N)」：N 含 Python 與 AI 工具，但只升級 npm＋Homebrew；改成標示實際範圍，並用 `viewModel.upgradeAllCommands` 在確認面板列出指令。「顯示 X / 全系統 Y」與側邊欄計數不一致（清單不含 AI 工具）。「待升級總覽」卡點了沒反應；弱點卡顯示「待更」。
- 移除套件時列上顯示升級進度與假百分比（`currentActionPackageId` 共用）；其他操作進行中時列上按鈕沒停用；資料庫移除沒有確認；資料庫啟停不檢查結果；sqlite 不是服務卻有「啟動」。
- 各頁「重新檢查」不設 loading 狀態、可重複觸發；掃描失敗顯示成「未找到套件」；「僅待升級」篩選為空時應顯示「全部最新」；安全頁未稽核就顯示「已驗證無弱點」。
- Python 頁：沒有全部升級、不顯示目前直譯器、PEP 668 環境仍顯示升級／移除。
- 安裝面板永遠預設 npm；AI 工具「檢查更新」實際執行升級；搜尋未去空白（用 `String.dkSearchKey`）；設定頁關掉稽核／自身更新後舊結果不清除；`locallyFixedGroupIds` 不重設；批次修復時卡片不顯示忙碌。
- 文案：「乾淨移除」「完全清除」與實際指令不符（npm/pip 只是 uninstall、資料庫資料目錄不刪）；「共 N 個 CVE」把 GHSA 也算進去且重複計算；統一用詞見 `DESIGN.md`。

## 驗證方式

- 完成標準：`swift build`（無警告）、`swift test`（目前 43 個）、`./bundle.sh` 與 `codesign --verify --deep --strict DevKeeper.app`、`open -n DevKeeper.app` 後 20 秒內無崩潰報告。
- 元件展示頁：`DEVKEEPER_GALLERY=1 .build/debug/DevKeeper`；`DEVKEEPER_GALLERY_SHOW=dropdown|tooltip|longtip|confirm|longmodal|modaldropdown` 直接打開浮層。選單列面板：`DEVKEEPER_SHOW_MENU_PANEL=1`（啟動 6 秒後打開、不自動關閉）。
- 截圖只截 DevKeeper 視窗：用 `CGWindowListCopyWindowInfo` 依 PID 找視窗編號，再 `screencapture -l <id> -o -x 檔案`。不要全螢幕截圖。
- **不要模擬滑鼠或鍵盤事件**：曾因 DevKeeper 視窗被 Brave 蓋住，點擊落到使用者的瀏覽器。真實的滑過、點擊、Esc、背景視窗第一下點擊仍未驗證，需請使用者手動確認。

## 待使用者決定或注意

- 使用者環境的相依衝突尚未還原（未獲同意）：`uv tool` 的 demo-agent、demo-app 為 filelock 4.2.4（要求 <4），demo-tool 為 libbaz 4.1.3（要求 <4）；Homebrew Python 3.11 的 demo-app 也有 filelock 衝突。建議用 `uv pip install --python <tool python> "filelock<4"` 等範圍指令，之後重跑 `uv pip check` 與稽核。
- 正式 App 的設定網域 `com.devkeeper.macos` 中 `showStatusBarItem = 0`（選單列圖示被關閉）。
