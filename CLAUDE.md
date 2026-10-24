# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 專案概述

DevKeeper：macOS 原生（SwiftUI，macOS 14+）開發者套件管理應用程式，聚合管理 npm 全域工具、pip、Homebrew（formulae/casks）、本機資料庫服務、AI CLI 工具，並做安全弱點稽核。UI 文字為繁體中文。SwiftPM 專案（`Package.swift`，tools 5.10，無外部依賴），分三個 target：`DevKeeperCore`（僅依賴 Foundation 的共用邏輯）、`devkeeper-cli`（可在 Linux 跑的命令列版）、`DevKeeper`（SwiftUI app，只在 macOS 才加入 `Package.swift`）。

## 指令

```bash
swift build                 # debug 編譯（Linux 上只有 Core 與 CLI）
swift run DevKeeper         # 直接執行 macOS app（無 .app bundle，版本號會取到後備值）
swift run devkeeper-cli scan            # CLI：version / scan / python list / audit / fix，多數支援 --json
swift test                              # 跑 DevKeeperCoreTests（純邏輯測試）
swift test --filter PythonLogicTests/testName   # 跑單一測試
swift run devkeeper-cli serve           # 本機網頁介面（Linux 的圖形介面），印出含金鑰的網址
swift build -c release --product devkeeper-cli  # 只編 CLI（Linux CI 用法）
./bundle.sh                 # release 編譯 + 產生 icon + 寫 Info.plist + ad-hoc codesign + 打包 DevKeeper.app / DevKeeper.dmg
```

- 沒有 lint 設定。CI（`.github/workflows/ci.yml`）在 macOS 與 Linux（swift 5.10 / 6.0）跑 build + test + CLI smoke test；`audit` 發現弱點時 exit 1，CLI 在 CI 以此判斷。
- 發版版本號寫死在 `bundle.sh` 的 `VERSION` / `BUILD`（Info.plist 由該腳本產生，repo 內沒有 plist 檔）。`DevKeeper.app`、`DevKeeper.dmg`、`.build` 皆為產物。
- 圖示由 `scripts/generate_icon.swift` 以程式繪製，非靜態資源。

## 架構

- **Target 分工**：所有不依賴 UI 的邏輯在 `Sources/DevKeeperCore/`（`Models/`、`Services/`、`Engine/`），app 與 CLI 共用，因此 Core 內只能用 Foundation，平台差異用 `#if os(Linux)` / `#if os(macOS)`（例如 `ShellExecutor` 在 Linux 用 `/bin/sh`、macOS 用 zsh；`AptService` 供 Linux）。Core 的型別與方法要加 `public` 才能被 app / CLI 使用。`Engine/Engines.swift`（`AuditEngine`、`InterpreterChoice` 等純函式）放 app 與 CLI 必須行為一致的流程；改稽核／修復／直譯器選擇邏輯優先放這裡，並在 `Tests/DevKeeperCoreTests/` 補測試。
- **CLI**：`Sources/devkeeper-cli/main.swift` 單檔，自行解析參數（`--json --yes --dry-run --all --projects`，`DEVKEEPER_PROJECTS` 環境變數），不用 ArgumentParser。
- **本機網頁介面（Linux 的 GUI）**：`devkeeper-cli serve` 啟動 `Core/Web/` 內手寫的 HTTP/1.1 server（`LocalHTTPServer`，只綁 127.0.0.1，一連線一請求）。`WebApp` 提供唯讀的 `/api/scan`、`/api/python`、`/api/audit` 與單頁 `WebUI.html`（內嵌字串，只用 `textContent` 塞資料），資料來自與 CLI 共用的 `ReportBuilder`（`Services/Reports.swift`）。防護集中在 `RequestGuard`：僅 GET、Host 必須是 loopback 加本機 port（防 DNS rebinding）、隨機 token（API 只收 Bearer header，`?token=` 只給 HTML 頁），回應帶 nonce 式 CSP。第一版沒有任何會修改系統的端點，加修復功能前要重新評估這些防護。
- **單一 ViewModel**：`ViewModels/AppViewModel.swift`（`@MainActor ObservableObject`，約 900 行）持有所有 `@Published` 狀態（各類套件清單、掃描/操作進度、日誌、更新資訊），經 `.environmentObject` 注入所有 View。所有 scan / upgrade / uninstall / install 流程都在這裡協調；`NavigationTab` enum 也定義於此，新增頁面要同步改它與 `MainView`。
- **Services/**（在 `DevKeeperCore`；`StatusBarController`、`FileSystemWatcher`、`LegacyCleanup` 例外，在 `Sources/DevKeeper/Services/`）：無狀態包裝，每個生態系一個（`NpmService`、`PythonService`、`BrewService`、`DatabaseService`、`AIToolService`、`SecurityService`、`GitHubReleaseService`），皆透過 `ShellExecutor.shared` 呼叫 CLI 並解析輸出，或呼叫 npm registry / PyPI / GitHub API。
- **ShellExecutor**：以 `/bin/zsh -c`（Linux 為 `/bin/sh -c`）執行指令，自行組合 PATH（Homebrew、nvm、fnm、cargo、`~/.local/bin`），因為 GUI app 不繼承終端機 PATH。`run` 在非零結束但 stdout 有內容時仍視為成功（`npm list` 有 peer dep 警告時會非零）；`stream` 回傳 `AsyncStream` 供日誌面板即時顯示。
- **自動重新整理**：`FileSystemWatcher` 用 `DispatchSource` 監看 `/Applications`、Homebrew Cellar/Caskroom、npm global `lib/node_modules` 等目錄（2 秒 debounce）；另有每 30 分鐘 Timer。兩者都在 `isActionRunning` 時跳過，避免與進行中的操作衝突。README 提到 FSEvents，實作是 DispatchSource。
- **Models/**（在 `DevKeeperCore`）：`PackageItem`（npm/python/brew 共用）、`AIToolItem`、`SecurityItem`、`ExecutionLog`。
- **Views/**：每個 `NavigationTab` 一個頁面；共用元件在 `Views/Components/`，視覺常數在 `Views/Theme.swift`。`StatusBarController`（Services/）管理選單列項目，內容為 `MenuBarView`。
- **Python 環境偵測**：`PythonInterpreterService` 偵測系統／Homebrew／pyenv／uv 的直譯器（以 realpath 去重；沒有 Xcode 命令列工具時不碰 `/usr/bin/python3` 以免跳系統視窗），`PythonRuntime` 是同步的「目前使用的直譯器」持有者（`PythonService`、`FixCommandBuilder` 等非 async 程式碼組指令時用它），預設自動挑仍受支援且可寫入的版本（`PythonLifecycle` 內建 python.org 的支援時程表）。帶 PEP 668 `EXTERNALLY-MANAGED` 標記的直譯器只讀取、拒絕 pip 寫入。
- **漏洞修復流程**：`scanSecurityAudit` 掃描每個直譯器與每個 uv tool venv，`VulnerabilityItem.environment` 記錄所在環境；`PackageVulnerabilityGroup` 把同一套件跨環境合併成一張卡（`fixTargets` 每環境一個修復指令，失敗原因與替代方案以 `group.key(for:)` 分環境儲存）。`AppViewModel.executeFix` 修完會實際檢查已安裝版本，不信任 exit status。修不了時 `PythonEnvironmentService.plan` 用 `pip inspect` 相依圖產生「移除」或「搬到 uv tool 獨立環境」計畫（新環境全部成功才移除舊的）。uv tool 環境只升級單一套件（`uv pip install --python`），不用 `uv tool upgrade`（會重新解析整個相依樹）。
- **系統內建 Python（Xcode）的例外**：macOS 的 `/usr/bin/python3` 是 Xcode 命令列工具附的 3.9.6，使用者無法升級。`isBuiltInException` 預設隱藏它的 pip／setuptools／wheel 漏洞（修復版本需 Python 3.10+）；`PythonDependencyGraph.baseTooling` 內的套件任何情況下都不會被移除計畫處理。沒有命令列工具時不可執行 `/usr/bin/python3`（會跳系統安裝視窗）。位置在 `/Xcode.app/` 或 `/CommandLineTools/` 內的套件（`PythonEnvironmentService.isOSManagedLocation`，依 `pip list -v` 的 location）完全不稽核。
- **App 入口**：`App.swift` 強制深色（`.preferredColorScheme(.dark)`）、隱藏標題列、`.regular` activation policy。
- **自我更新檢查**：`checkSelfUpdate` 向 GitHub `liaw-boy/DevKeeper` 的最新 release 比對版本，僅提示，不會自動安裝。

## 慣例

- 介面不使用 Emoji，圖示一律 SF Symbols，遵循 Apple HIG（README 的設計要求）。
