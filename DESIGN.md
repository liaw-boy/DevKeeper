# DevKeeper 設計規格

所有畫面只用這一套規格。規格的實作在 `Sources/DevKeeper/Design/`；新畫面只能使用那裡的 token 與元件，不另外寫顏色、字級或手刻按鈕。

執行 `DEVKEEPER_GALLERY=1 .build/debug/DevKeeper` 會開啟元件展示頁，左右並排顯示淺色與深色。加上 `DEVKEEPER_GALLERY_SHOW=dropdown|tooltip|longtip|confirm|longmodal|modaldropdown` 可在啟動時直接打開浮層，方便截圖檢查。

## 原則

- 極簡、中性：單色為主，用細邊線分隔，不用漸層、發光、彩色底色。
- 支援淺色與深色；設定頁可選「跟隨系統／淺色／深色」。
- 不使用 Apple 原生控制項（`Menu`、`Picker`、`Toggle`、`confirmationDialog`、`ProgressView`、`.sheet`、`.help`、`Link`、`NavigationSplitView`、`NSOpenPanel`），一律改用 `DK` 元件。視窗左上角的關閉、縮小、放大按鈕保留。
- 正常狀態不上色；只有需要注意的狀態才用顏色，而且只用在文字。

## Token（`DKTokens.swift`）

| 用途 | Token | 淺色 | 深色 |
|---|---|---|---|
| 視窗底色 | `DK.background` | #FAFAF9 | #161618 |
| 卡片、輸入框、浮層 | `DK.surface` | #FFFFFF | #1E1E21 |
| 滑過、選取 | `DK.surfaceHover` | #F2F2F0 | #26262A |
| 邊線 | `DK.border` | #E4E4E0 | #2E2E32 |
| 主要文字 | `DK.textPrimary` | #1A1A19 | #EDEDEC |
| 次要文字 | `DK.textSecondary` | #6B6B68 | #A1A1A0 |
| 第三層文字 | `DK.textTertiary` | #9C9C98 | #6E6E6C |
| 主要按鈕（反白） | `DK.inverseBackground` / `DK.inverseText` | 深底白字 | 淺底深字 |
| 危險、重大版本、完成（只用於文字） | `DK.danger` / `DK.warning` / `DK.success` | | |

字級只有五種，不用半點數，不用 bold：

| 用途 | Token | 大小 |
|---|---|---|
| 頁面標題 | `DK.Font.title` | 20 semibold |
| 區塊、卡片、面板標題 | `DK.Font.heading` | 15 semibold |
| 內文、按鈕、清單名稱 | `DK.Font.body` / `bodyMedium` | 13 |
| 次要資訊 | `DK.Font.caption` | 12 |
| 標籤、計數 | `DK.Font.micro` | 11 medium |
| 版本、指令、路徑 | `DK.Font.mono` | 12 等寬 |

- 間距只用 `DK.Space`：元素之間用 4、8、12、16、24、32；2、6、10（`xxs`、`tight`、`snug`）只用在控制項內部的留白。頁面左右留白一律 `DK.pagePadding`（24），標題與內容對齊。
- 圓角：控制項 `DK.Radius.control`（6），卡片與面板 `DK.Radius.card`（10），控制項內的巢狀元素（分段選取底色、選單列）`DK.Radius.inner`（4）。標籤、徽章不用膠囊形；開關軌道是唯一的圓端外形。
- 控制項高度 `DK.controlHeight`（28），清單列內的小按鈕 `DK.compactControlHeight`（24）。
- 邊線一律 1pt。只有浮層（下拉面板、提示、對話面板）有淡陰影。
- 圖示：SF Symbols、單色、次要文字色；大小用 `DK.Icon`：一般 13、勾選與欄位內圖示 11、箭頭與清除鈕 9。只用在側邊欄、純圖示按鈕和必須靠圖示表意的狀態。標題、卡片標題、文字按鈕、統計數字旁不放圖示。
- 動態：按下只降透明度（`DKPressStyle`），滑過換底色；過場 0.12 秒淡入淡出。不用彈跳、縮放、位移動畫。

## 元件

| 元件 | 用途 |
|---|---|
| `DKButton` | 主要、次要、危險、純文字四種；整塊可點、文字不換行；執行中顯示轉圈；停用時用 `disabledReason` 說明原因 |
| `DKIconButton` | 純圖示按鈕，必須給 `help` |
| `DKActionMenu` | 圖示按鈕加操作清單 |
| `DKDropdown` | 取代 `Menu`、`Picker` |
| `DKSegmented` | 所有篩選切換 |
| `DKSwitch` | 取代 `Toggle` |
| `DKTextField`、`DKSearchField` | 輸入與搜尋；搜尋比對用 `String.dkSearchKey`（去前後空白、小寫） |
| `DKSpinner`、`DKProgressBar` | 取代 `ProgressView`；只有真實進度才給數值 |
| `DKTag` | 標籤：無底色、細邊框，只靠文字顏色區分 |
| `DKStatusText` | 套件升級狀態，純文字 |
| `.dkCard()`、`DKDivider` | 唯一的卡片樣式與分隔線 |
| `DKPageHeader`、`DKSectionTitle` | 頁面標題列與區塊標題 |
| `DKEmptyState` | 載入中、尚未檢查、沒有資料、全部最新、發生錯誤 |
| `DKCommandBlock` | 指令：等寬、可選取、可複製 |
| `DKModalPanel`、`DKConfirmPanel` | 視窗內對話面板；會改動系統的操作一律先用 `confirm` 列出實際指令 |
| `.dkTooltip()` | 取代 `.help`；可能被截斷的文字要加上，滑過時顯示全文 |
| `DKSettingRow` | 設定列 |

浮層（下拉面板、提示、對話面板）由 `DKOverlayHost` 統一繪製。每個視窗或面板的根畫面都要包一層 `DKOverlayHost`；元件透過 `@Environment(\.dkOverlay)` 取得，找不到時不會閃退，只是不顯示浮層。

## 文案

- 統一用詞：升級（不用「更新」）、檢查（不用「掃描、同步、重新整理」）、移除（不用「乾淨移除、解除安裝」）、弱點（不用「漏洞」）、登入時啟動（不用「開機」）。
- 嚴重程度：嚴重、高、中、低、未知。
- 不用：一鍵、立即、全面、深度、國際、次世代、為您、最佳、即時、之、驚嘆號、Emoji。
- 英文只保留專有名詞（npm、Homebrew、pip、GitHub、OSV、CVE 編號）。
- 中文用全形標點：「：」「（）」「…」。
- 按鈕文字盡量 4 個字以內。
- 文案必須和程式行為一致：npm、Python 的移除只執行 uninstall；移除資料庫不會刪除資料目錄；計數寫「N 個弱點（M 個套件）」，GHSA 不算成 CVE。
