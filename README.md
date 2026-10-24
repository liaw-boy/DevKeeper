<div align="center">

# DevKeeper

**開發者套件管理與安全弱點稽核**

一個畫面管理 npm、pip、Homebrew、本機資料庫與 AI CLI 工具，並找出已知的安全弱點。

[![CI](https://github.com/liaw-boy/DevKeeper/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/liaw-boy/DevKeeper/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/liaw-boy/DevKeeper)](https://github.com/liaw-boy/DevKeeper/releases/latest)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%7C%20Linux-lightgrey)

[安裝](#安裝) · [快速上手](#快速上手) · [功能](#功能) · [命令列版與網頁介面](#命令列版與網頁介面) · [Python 稽核與修復](#python-環境稽核與修復)

</div>

---

## 安裝

| 平台 | 內容 | 方式 |
|---|---|---|
| macOS 14+ | 圖形應用程式 | Homebrew 或下載 dmg |
| macOS / Linux | 命令列版 `devkeeper-cli` 與網頁介面 | 預編譯檔、Homebrew 或原始碼 |

### macOS 應用程式

```bash
brew tap liaw-boy/devkeeper https://github.com/liaw-boy/DevKeeper
brew install --cask devkeeper
```

也可以到 [Releases](https://github.com/liaw-boy/DevKeeper/releases/latest) 下載 `DevKeeper.dmg`，拖曳到「應用程式」。

> **第一次開啟會被 macOS 擋下。** 應用程式為 ad-hoc 簽署、未經 Apple 公證。先開啟一次，再到「系統設定 > 隱私權與安全性」按「仍要打開」。

自行打包：

```bash
./bundle.sh        # 產生 DevKeeper.app 與 DevKeeper.dmg
```

### 命令列版（Linux 與 macOS）

<details open>
<summary><b>下載預編譯檔</b>（Linux x86_64，不需要 Swift）</summary>

```bash
curl -LO https://github.com/liaw-boy/DevKeeper/releases/latest/download/devkeeper-cli-linux-x86_64.tar.gz
curl -LO https://github.com/liaw-boy/DevKeeper/releases/latest/download/devkeeper-cli-linux-x86_64.tar.gz.sha256
sha256sum -c devkeeper-cli-linux-x86_64.tar.gz.sha256
tar xzf devkeeper-cli-linux-x86_64.tar.gz
sudo install devkeeper-cli /usr/local/bin/
```

</details>

<details>
<summary><b>Homebrew</b>（Linuxbrew，x86_64）</summary>

```bash
brew tap liaw-boy/devkeeper https://github.com/liaw-boy/DevKeeper
brew install devkeeper-cli
```

</details>

<details>
<summary><b>從原始碼編譯</b>（需要 Swift 5.10 以上；ARM 與 macOS 用這個）</summary>

```bash
git clone https://github.com/liaw-boy/DevKeeper && cd DevKeeper
swift build -c release --product devkeeper-cli
.build/release/devkeeper-cli version
```

</details>

---

## 快速上手

### macOS 應用程式

1. **開啟並看總覽**：左側欄切到「總覽」，會顯示各類套件的待升級數量與上次檢查時間。有已知安全弱點時，頁面上方會出現安全警報。
2. **升級套件**：到「npm 套件」「Python 套件」或「Homebrew」，在套件旁按「更新」升級單一套件，或按「更新全部」一次升級；頁面右上角「重新檢查」會重新向官方來源查詢版本。
3. **安裝套件**：按「安裝套件」，選擇目標環境、輸入套件名稱，再按「開始完整安裝」；輸出會即時顯示在「執行日誌」。
4. **乾淨移除**：在套件旁按移除圖示，確認後會連同殘留設定一起清掉。
5. **處理安全弱點**：切到「安全弱點稽核」，按「全面安全弱點稽核」。每張卡片是一個受影響的套件，列出目前版本、建議的安全版本與 CVE；按「一鍵修復」修單一套件，或按「一鍵修復所有弱點」。
   - 升級不了時，畫面會提出「搬到獨立環境」或「移除套件」的替代方案，按「確認搬移」或「確認移除」才會執行。
   - 無法修復的風險可按「忽略此風險」；被忽略的項目可用「全部還原」重新列出。
   - 要稽核自己的專案，按「自選特定專案資料夾進行稽核」，或到「偏好設定」指定專案資料夾。
6. **調整設定**：「偏好設定」可選背景掃描頻率（15 分鐘、30 分鐘、1 小時、6 小時）、是否在選單列顯示、是否開機啟動，以及是否通知 DevKeeper 本身的新版本。

### 命令列版

典型流程是「看狀況、找弱點、預覽修復、執行修復」：

```bash
# 1. 看有哪些東西可以升級
devkeeper-cli scan

# 2. 稽核安全弱點（有弱點時結束代碼為 1，可用在 CI）
devkeeper-cli audit

# 3. 先預覽修復會執行哪些指令，不會改動任何東西
devkeeper-cli fix --dry-run

# 4. 確認後執行
devkeeper-cli fix
```

`audit` 的輸出類似下面這樣（套件名稱與編號為範例）：

```
1 個套件存在弱點，共 2 個 CVE

[高] example-lib  Python 3.12 (Homebrew)
    版本 1.2.0 → 安全版本 1.2.5
    CVE-2026-0001、CVE-2026-0002
```

| 結束代碼 | 意義 |
|---|---|
| `0` | 沒有待處理項目 |
| `1` | `audit` 發現弱點 |
| `2` | `fix` 後仍有無法修復的項目 |
| `64` | 指令或參數錯誤 |

> **修復前請先預覽。** `fix` 會真的升級、搬移或移除套件，而且是直接升到「沒有已知弱點的版本」。某個套件可能被其他套件限制了版本範圍，升級後這些套件會不相容。執行後建議在受影響的環境跑 `uv pip check`（uv 環境）或 `python3 -m pip check`，確認沒有出現不相容的警告。

需要自動化時加上 `--json`；稽核專案目錄用 `--projects 路徑`（也可用環境變數 `DEVKEEPER_PROJECTS`）。直接升級會立刻執行；搬移或移除這類替代修復，不加 `--yes` 時只會列出計畫就結束（結束代碼 2），加上 `--yes` 才會執行。

### 網頁介面

1. 執行 `devkeeper-cli serve`。
2. 把終端機印出的網址（含 `?token=…`）貼到瀏覽器。
3. 三個分頁：**概覽**（各類套件的待升級清單）、**Python 環境**（偵測到的直譯器與支援期限）、**安全稽核**（弱點清單與修復指令）。「重新整理」會重新掃描，結果會快取 10 秒。
4. 在遠端伺服器上用時，先在本機執行 `ssh -L 8765:127.0.0.1:8765 user@server`，再開網址。
5. 修復不會在網頁上執行；複製頁面上的指令，或回終端機用 `devkeeper-cli fix`。

### 常見問題

| 狀況 | 處理 |
|---|---|
| macOS 說「無法打開 DevKeeper」 | 應用程式未公證。先開啟一次，再到「系統設定 > 隱私權與安全性」按「仍要打開」。 |
| `serve` 說連接埠被占用 | 換一個埠：`devkeeper-cli serve --port 9000`；`--port 0` 會自動挑一個空的。 |
| 網頁顯示「驗證失敗」 | 金鑰每次啟動都會變，請用最新印出的網址重新開啟。 |
| `audit` 沒找到任何 Python | 確認 `python3` 在 PATH 中，且有安裝 pip。 |
| 修不了的 Python 套件 | 受 PEP 668 保護的 Python 只讀取；改用 uv 或虛擬環境，或使用「搬到獨立環境」。 |

---

## 功能

| 類別 | 說明 |
|---|---|
| **npm 全域工具** | 追蹤本機全域安裝的 Node.js CLI 工具，自動比對 npm Registry 的最新版本。 |
| **Python 套件（pip）** | 檢索各 Python 環境中安裝的套件，向 PyPI 查詢最新版本與安全性更新。 |
| **Homebrew** | 支援 Formulae（命令列工具）與 Casks（圖形應用程式）的過期檢查與相依管理。 |
| **資料庫與背景服務** | 啟動、停止、重啟與監控 PostgreSQL、MySQL、Redis、MongoDB、MariaDB。 |
| **安全稽核** | 掃描所有 Python 環境、`uv tool` 與 npm 的已知弱點，並提供修復。 |
| **自動重新整理** | 監看應用程式與套件目錄的變動，在 VS Code、iTerm 或終端機安裝、移除套件後自動更新清單。 |
| **安裝與乾淨移除** | 原生安裝視窗，輸出即時串流到日誌面板；移除時一併清理殘留。 |

### 乾淨移除

| 對象 | 做法 |
|---|---|
| Cask 應用程式 | 使用 `--zap`，清除 `~/Library/Application Support/`、`Caches/`、`Preferences/` 內的關聯檔案。 |
| Formulae 工具 | 自動執行 `brew autoremove`，清掉不再需要的相依項目。 |
| npm / Python | 從全域路徑與符號連結中移除。 |

### 介面

- 遵循 macOS Human Interface Guidelines，介面沒有 Emoji，圖示全部使用 SF Symbols。
- 使用系統強調色與原生毛玻璃材質。

---

## 命令列版與網頁介面

SwiftUI 應用程式只能在 macOS 執行。Linux 與其他環境使用 `devkeeper-cli`，圖形介面是它內建的本機網頁。

| 指令 | 作用 |
|---|---|
| `scan` | 待升級套件總覽（Python、npm、pip、系統套件） |
| `python list` | 列出偵測到的 Python 與支援狀態 |
| `audit` | 安全弱點稽核，發現弱點時結束代碼為 1 |
| `fix` | 修復弱點；`--dry-run` 只顯示會執行的指令，`--yes` 直接執行替代修復 |
| `serve` | 啟動本機網頁介面 |
| `version` | 顯示版本 |

常用選項：`--json` 以 JSON 輸出、`--all` 連內建例外也顯示、`--projects 路徑` 一併稽核專案的 `package.json` 與 `requirements.txt`、`--port 埠號` 指定 `serve` 的連接埠（預設 8765）。

### 網頁介面

```bash
devkeeper-cli serve
```

指令會印出一組含一次性金鑰的網址，例如 `http://127.0.0.1:8765/?token=…`，用瀏覽器開啟即可查看概覽、Python 環境與安全稽核。

- 只監聽 `127.0.0.1`，**唯讀**，不會修改系統；需要修復請用 `devkeeper-cli fix`。
- 金鑰每次啟動重新產生；沒有金鑰、金鑰錯誤或 Host 不是本機的請求一律拒絕。
- 頁面會顯示本機的套件版本、CVE 與路徑，請不要把連接埠轉發到不信任的網路。
- 在遠端伺服器上使用時，用 SSH 轉發再從本機瀏覽器開啟：

  ```bash
  ssh -L 8765:127.0.0.1:8765 user@server
  ```

> Linux 的系統套件目前只支援 apt（Debian、Ubuntu 系）；其他發行版只會顯示 npm 與 Python。

---

## Python 環境稽核與修復

- **全環境稽核**：掃描每個 Python（系統、Homebrew、pyenv、uv）與每個 `uv tool` 獨立環境。同一套件跨環境合併成一張卡，可依序一鍵修復，並有獨立的進度條。
- **修不了時的替代做法**：先嘗試直接升級；升級不了（例如修復版本要求較新的 Python）時，自動規劃「把命令列工具搬到 uv 獨立環境」或「移除沒人使用的套件」，整批只需確認一次。新環境全部成功才會移除舊的，失敗不會動到舊環境。需要 [uv](https://docs.astral.sh/uv/)。
- **例外與忽略**：無法修復的已知風險可以標記忽略，僅針對當時的版本，升級後會重新檢查。
- **受保護的 Python**：帶有 PEP 668 `EXTERNALLY-MANAGED` 標記的直譯器只讀取與掃描，不會用 pip 直接修改。
- **基礎工具**：`pip`、`setuptools`、`wheel` 屬於環境本身，不會被移除計畫處理。

<details>
<summary><b>關於 macOS 內建 Python（Xcode / 命令列工具）</b></summary>

macOS 本身不附 Python 3。`/usr/bin/python3` 只是轉接頭，真正的 Python（例如 3.9.6，實際版本依你的 Xcode 或命令列工具而定）由 Apple 編譯後放在 **Xcode 命令列工具**或 `Xcode.app` 的 `Python3.framework` 裡，依 `xcode-select -p` 轉接過去，推測主要供 LLDB 等 Apple 開發工具使用。版本由 Apple 決定，使用者無法單獨升級；例如 Python 3.9 已於 2025-10-31 終止支援。

它附帶的 `pip`、`setuptools`、`wheel` 版本較舊，而這些套件的修復版本都要求 Python 3.10 以上，所以無法在該 Python 內修復。

DevKeeper 的處理方式：

- 沒有安裝命令列工具時，不會執行 `/usr/bin/python3`，避免跳出系統的「安裝開發者工具」視窗。
- 不會把它當作預設使用；它是 Apple 的檔案，無法移除或升級。
- 套件實際位置在 Xcode 或命令列工具資料夾內的（Apple 隨附，只有 Apple 能更新）**不納入稽核**；你自己安裝進該 Python 的套件（例如在 `~/Library/Python/3.9`）仍會照常稽核。
- `pip`、`setuptools`、`wheel` 的漏洞預設列為**內建例外**並隱藏。安全稽核頁會顯示已忽略的數量，可以「全部還原」重新顯示；其他安裝在該 Python 裡的套件照常稽核與修復。

**建議做法**：不要把套件裝進它，改用 uv 或 Homebrew 的 Python，每個專案與工具各用自己的虛擬環境。已經裝進去的套件，可用安全稽核頁的「搬到獨立環境」或「移除套件」清理。

</details>

---

## 開發

```bash
swift build                          # 編譯（Linux 上只有共用核心與 CLI）
swift test                           # 執行測試
swift run DevKeeper                  # 執行 macOS 應用程式
swift run devkeeper-cli serve        # 執行網頁介面
```

專案分成三個 target：`DevKeeperCore`（只依賴 Foundation 的共用邏輯）、`devkeeper-cli`（命令列版）、`DevKeeper`（SwiftUI 應用程式，只在 macOS 編譯）。CI 在 macOS 與 Linux（Swift 5.10、6.0）上執行編譯、測試與 CLI 煙霧測試。
