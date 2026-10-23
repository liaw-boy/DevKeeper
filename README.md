# DevKeeper

DevKeeper 是一款專為 macOS 量身打造的原生開發者套件與版本管理應用程式（Swift 6 + SwiftUI），嚴格遵循 Apple Human Interface Guidelines 設計語言。

---

## 核心功能與特性

### 1. 全域套件與多環境聚合管理
* **npm 全域工具**：追蹤與管理本機全域安裝之 Node.js CLI 工具（包含 Claude Code 等），自動比對 npm Registry 最新發布版本。
* **Python 套件 (pip)**：檢索本機 Python 執行環境中安裝之第三方庫，並向 PyPI 查詢最新版本與安全性更新。
* **Homebrew 軟體與工具**：完整支援 Formulae（命令列工具）與 Casks（macOS 圖形應用程式）之過期檢驗與依賴管理。
* **資料庫與背景服務**：內建對 PostgreSQL、MySQL、Redis、MongoDB、MariaDB 等本機資料庫服務的生命週期管理（啟動、停止、重啟與狀態監控）。

### 2. 即時自動感應（FSEvents）
* 整合 macOS 系統底層之 `FSEventStream` 檔案變更事件監聽機制。
* 無論使用者於 VS Code、iTerm 或系統終端機執行安裝或移除操作，DevKeeper 皆能在目錄變更時於背景自動重新整理，無須手動按鈕更新。

### 3. 一鍵安裝與乾淨移除（Clean Uninstall）
* **完整安裝**：提供原生安裝彈窗，可直接依環境類型快速安裝新套件，並將終端輸出即時串流至日誌面板。
* **徹底乾淨移除**：
  * **Cask 應用程式**：採用 `--zap` 旗標，全數清除該應用程式遺留於 `~/Library/Application Support/`、`~/Library/Caches/` 與 `~/Library/Preferences/` 的所有關聯檔案與快取。
  * **Formulae 工具**：自動觸發 `brew autoremove`，清除無用之孤立相依項目，確保不殘留冗餘檔案。
  * **npm / Python**：乾淨自全域路徑與符號連結中移除。

### 4. Apple 原生設計標準
* 嚴格遵循 macOS HIG，全介面無任何 Emoji、無螢光或科幻色彩。
* 圖標全數採用 Apple 官方 SF Symbols 向量符號。
* 動態自適應系統淺色（Light Mode）與深色模式（Dark Mode），採用原生毛玻璃材質與系統強調色。

### 5. Python 版本與環境管理
* **偵測所有 Python**：系統、Homebrew、pyenv、uv 安裝的版本，標示來源、位置與支援狀態（依 python.org 發布時程，已終止支援者以紅色警告）。
* **升級與安裝**：Homebrew、uv、pyenv 管理的版本可一鍵升級；可安裝仍在支援期內的新版本；沒有 uv 時可一鍵安裝。
* **終端機 `python3` 指向新版**：透過 uv 在 `~/.local/bin` 建立指令，不動系統內建的 Python。
* **全環境安全稽核**：掃描每個 Python 與每個 `uv tool` 獨立環境；同一套件跨環境合併成一張卡，一鍵依序修復。
* **修不了時的替代做法**：先嘗試直接升級；升級不了（例如修復版本要求較新的 Python）時，自動規劃「把命令列工具搬到 uv 獨立環境」或「移除沒人使用的套件」，整批只需確認一次。新環境全部成功才移除舊的，失敗不會動舊環境。
* **專案虛擬環境重建**：找出用舊版 Python 建立的虛擬環境，一鍵以新版重建並重新安裝套件；舊環境先備份，失敗自動還原，有程式正在使用時拒絕重建。
* **例外與忽略**：無法修復的已知風險可標記忽略（僅針對當時的版本，升級後自動重新檢查）。
* 受 PEP 668 保護的 Python（`EXTERNALLY-MANAGED`）只讀取與掃描，不會用 pip 直接修改。

#### 關於系統內建 Python（Xcode / 命令列工具）
* macOS 本身不附 Python 3。`/usr/bin/python3` 只是轉接頭，真正的 Python（例如 3.9.6，實際版本依你的 Xcode 或命令列工具而定）是 Apple 編譯後放在 **Xcode 命令列工具**或 `Xcode.app` 的 `Python3.framework` 裡，由 `/usr/bin/python3` 依「目前使用的開發工具」（`xcode-select -p`）轉接過去，推測主要供 LLDB 等 Apple 開發工具使用。版本由 Apple 決定，使用者無法單獨升級；例如 Python 3.9 已於 2025-10-31 終止支援。
* 它附帶的 `pip`、`setuptools`、`wheel` 版本較舊，而這些套件的修復版本都要求 Python 3.10 以上，無法在該 Python 內修復。
* DevKeeper 的處理方式：
  * 沒有安裝命令列工具時，不會執行 `/usr/bin/python3`，避免跳出系統的「安裝開發者工具」視窗。
  * 不會把它當作預設使用，也不提供升級；來源顯示為「Apple 內建」，標示「無法移除或升級」。
  * 套件的實際位置在 Xcode 或命令列工具資料夾內的（Apple 隨附、只有 Apple 能更新），**不納入稽核**；你自己安裝進該 Python 的套件（例如在 `~/Library/Python/3.9`）仍會照常稽核。
  * 其中 `pip`、`setuptools`、`wheel` 的漏洞預設列為**內建例外**並隱藏（安全稽核頁會顯示已忽略的數量，可「全部還原」重新顯示）。其他安裝在該 Python 裡的套件仍會照常稽核與修復。
* 建議做法：不要把套件裝進它；改用 uv 或 Homebrew 的 Python，每個專案與工具各用自己的虛擬環境。已經裝進去的套件，可用安全稽核頁的「搬到獨立環境」或「移除套件」清理。
* 用它建立的虛擬環境（`pyvenv.cfg` 的 `home` 指向 Xcode）會被視為舊版本，可在「Python 版本」頁的「專案虛擬環境」重建。

---

## 快速啟動方式

可以直接透過以下指令於 Mac 螢幕上啟動獨立應用程式：

```bash
open DevKeeper.app
```

或打開 DMG 安裝檔拖曳至「應用程式」目錄：
```bash
open DevKeeper.dmg
```
