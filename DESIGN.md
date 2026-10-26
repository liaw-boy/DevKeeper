# DevKeeper 設計規格

所有畫面只用這一套規格。規格的實作在 `Sources/DevKeeper/Design/`；新畫面只能使用那裡的 token 與元件，不另外寫顏色、字級或手刻按鈕。

執行 `DEVKEEPER_GALLERY=1 .build/debug/DevKeeper` 會開啟元件展示頁，左右並排顯示淺色與深色。加上 `DEVKEEPER_GALLERY_SHOW=dropdown|tooltip|longtip|confirm|longmodal|modaldropdown` 可在啟動時直接打開浮層，方便截圖檢查。

## 原則

- 柔和、中性：單色為主，用細邊線分隔，不用漸層、發光。唯一的彩色是低飽和藍強調色，加上套件來源標章的品牌色。
- 支援淺色與深色；設定頁可選「跟隨系統／淺色／深色」。
- 不使用 Apple 原生控制項（`Menu`、`Picker`、`Toggle`、`confirmationDialog`、`ProgressView`、`.sheet`、`.help`、`Link`、`NavigationSplitView`、`NSOpenPanel`），一律改用 `DK` 元件。視窗左上角的關閉、縮小、放大按鈕保留。
- 正常狀態不上色；需要注意的狀態用 `danger`／`warning` 顏色（文字、數字、嚴重度分段條）。強調色只用在選取、進度與比例條、連結與焦點。

## Token（`DKTokens.swift`）

| 用途 | Token | 淺色 | 深色 |
|---|---|---|---|
| 視窗底色 | `DK.background` | #FAFAF9 | #161618 |
| 卡片、輸入框、浮層 | `DK.surface` | #FFFFFF | #1E1E21 |
| 側邊欄底色 | `DK.surfaceSunken` | #F2F2F0 | #111113 |
| 滑過 | `DK.surfaceHover` | #F2F2F0 | #26262A |
| 強調色（選取圖示與文字、比例條） | `DK.accent` | #3B6FD8 | #7AA2F7 |
| 選取列底色 | `DK.accentSubtle` | #E8EFFC | #1E2A44 |
| 邊線 | `DK.border` | #E4E4E0 | #2E2E32 |
| 主要文字 | `DK.textPrimary` | #1A1A19 | #EDEDEC |
| 次要文字 | `DK.textSecondary` | #6B6B68 | #A1A1A0 |
| 第三層文字 | `DK.textTertiary` | #9C9C98 | #6E6E6C |
| 主要按鈕（反白） | `DK.inverseBackground` / `DK.inverseText` | 深底白字 | 淺底深字 |
| 危險、重大版本、完成（只用於文字） | `DK.danger` / `DK.warning` / `DK.success` | | |

字級只有六種，不用半點數，不用 bold（唯一例外見下）：

| 用途 | Token | 大小 |
|---|---|---|
| 頁面標題 | `DK.Font.title` | 20 semibold |
| 區塊、卡片、面板標題 | `DK.Font.heading` | 15 semibold |
| 內文、按鈕、清單名稱 | `DK.Font.body` / `bodyMedium` | 13 |
| 次要資訊 | `DK.Font.caption` | 12 |
| 標籤、計數 | `DK.Font.micro` | 11 medium |
| 版本、指令、路徑 | `DK.Font.mono` | 12 等寬 |
| 卡片大數字 | `DK.Font.display` | 28 semibold |

- 來源色（`DK.Brand`）是同一色相的柔和底色（淺色 14%、深色 22% 透明度）加同色圖示，不用黃或橘；只用在 `DKSourceBadge` 與 `DKPackageAvatar`。

- 間距只用 `DK.Space`：元素之間用 4、8、12、16、24、32；2、6、10（`xxs`、`tight`、`snug`）只用在控制項內部的留白。頁面左右留白一律 `DK.pagePadding`（24），標題與內容對齊。
- 圓角：控制項 `DK.Radius.control`（6），卡片與面板 `DK.Radius.card`（10），控制項內的巢狀元素（分段選取底色、選單列）`DK.Radius.inner`（4）。標籤、徽章不用膠囊形；開關軌道是唯一的圓端外形。
- 控制項高度 `DK.controlHeight`（28），清單列內的小按鈕 `DK.compactControlHeight`（24）。
- 邊線一律 1pt。卡片有極淡陰影（`DK.shadowSoft`），浮層（下拉面板、提示、對話面板）有較明顯的陰影。
- 圖示：SF Symbols；大小用 `DK.Icon`：一般 13、勾選與欄位內圖示 11、箭頭與清除鈕 9。側邊欄、卡片與套件列的圖示方塊用來源色（`DKSourceBadge`、`DKPackageAvatar`），其餘圖示維持單色、次要文字色。頁面標題、卡片標題不放圖示。文字按鈕可用 `DKButton(systemImage:)` 帶圖示。
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
| `DKIconTile` | 中性底色的單色圖示方塊 |
| `DKSourceBadge` | 套件來源（npm、Python、Homebrew、App、AI、資料庫）的柔和來源色圖示方塊，圖示由 `DKSource.symbol` 決定，不使用官方商標圖 |
| `DKPackageAvatar` | 單一套件的圖示：依名稱關鍵字選 SF Symbol（資料庫、鎖盾、終端機等），沒有對應時用來源預設圖示；底色與來源標章相同 |
| `DKBar`、`DKSegmentBar` | 比例條（例如可升級／全部）與分段條（弱點依嚴重度） |
| `DKMetricCard` | 緊湊的數據卡片：來源圖示、標題、數字與說明同一排，可選比例條；內容垂直置中，同排的卡片等高；窄卡片用 `captionBelow` 並讓說明單行 |
| `DKPageHeader`、`DKSectionTitle` | 頁面標題列與區塊標題 |
| `DKEmptyState` | 載入中、尚未檢查、沒有資料、全部最新、發生錯誤 |
| `DKCommandBlock` | 指令：等寬、可選取、可複製 |
| `DKModalPanel`、`DKConfirmPanel` | 視窗內對話面板；會改動系統的操作一律先用 `confirm` 列出實際指令 |
| `.dkTooltip()` | 取代 `.help`；可能被截斷的文字要加上，滑過時顯示全文 |
| `DKSettingRow` | 設定列 |

浮層（下拉面板、提示、對話面板）由 `DKOverlayHost` 統一繪製。每個視窗或面板的根畫面都要包一層 `DKOverlayHost`；元件透過 `@Environment(\.dkOverlay)` 取得，找不到時不會閃退，只是不顯示浮層。

## 頁面結構

- 側邊欄：頂部品牌區（強調色圖示方塊、名稱、待升級數量）；套件頁用來源色圖示方塊，其餘為單色圖示；數量用圓角小標籤，安全弱點只有大於 0 時才變紅。
- 清單頁（npm、Python、Homebrew）共用 `PackageListPage`：標題列、搜尋與篩選、`PackageRow` 清單。Homebrew 預設隱藏只因相依才安裝的套件，有待升級的仍會顯示。
- 詳細頁、安裝面板、批次修復確認都用 `DKModalPanel`，由 `overlay?.present` 開啟；不使用系統 sheet 或 `confirmationDialog`。
- 淺色與深色只透過 `DK` token 與 `Color.dkWash(_:)` 切換；不要寫死 `Color(red:)`、`.white`、`.black` 當背景。主控台輸出區用 `DK.surfaceSunken`。
- App 圖示（`scripts/generate_icon.swift`）是強調藍的圓角方塊加白色 `shippingbox.fill`，與側邊欄品牌區一致。

## 文案

- 統一用詞：升級（不用「更新」）、檢查（不用「掃描、同步、重新整理」）、移除（不用「乾淨移除、解除安裝」）、弱點（不用「漏洞」）、登入時啟動（不用「開機」）。
- 嚴重程度：嚴重、高、中、低、未知。
- 不用：一鍵、立即、全面、深度、國際、次世代、為您、最佳、即時、之、驚嘆號、Emoji。
- 英文只保留專有名詞（npm、Homebrew、pip、GitHub、OSV、CVE 編號）。
- 中文用全形標點：「：」「（）」「…」。
- 按鈕文字盡量 4 個字以內。
- 文案必須和程式行為一致：npm、Python 的移除只執行 uninstall；移除資料庫不會刪除資料目錄；計數寫「N 個弱點（M 個套件）」，GHSA 不算成 CVE。
