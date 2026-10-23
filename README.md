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
