# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 專案概述

DevKeeper：macOS 原生（SwiftUI，macOS 14+）開發者套件管理應用程式，聚合管理 npm 全域工具、pip、Homebrew（formulae/casks）、本機資料庫服務、GitHub release 追蹤的軟體、AI CLI 工具，並做安全弱點稽核。UI 文字為繁體中文。純 SwiftPM executable target（`Package.swift`，tools 5.10，無外部依賴、無測試 target）。

## 指令

```bash
swift build                 # debug 編譯
swift run DevKeeper         # 直接執行（無 .app bundle，版本號會取到後備值）
./bundle.sh                 # release 編譯 + 產生 icon + 寫 Info.plist + ad-hoc codesign + 打包 DevKeeper.app / DevKeeper.dmg
```

- 目前沒有測試與 lint 設定。
- 發版版本號寫死在 `bundle.sh` 的 `VERSION` / `BUILD`（Info.plist 由該腳本產生，repo 內沒有 plist 檔）。`DevKeeper.app`、`DevKeeper.dmg`、`.build` 皆為產物。
- 圖示由 `scripts/generate_icon.swift` 以程式繪製，非靜態資源。

## 架構

- **單一 ViewModel**：`ViewModels/AppViewModel.swift`（`@MainActor ObservableObject`，約 900 行）持有所有 `@Published` 狀態（各類套件清單、掃描/操作進度、日誌、更新資訊），經 `.environmentObject` 注入所有 View。所有 scan / upgrade / uninstall / install 流程都在這裡協調；`NavigationTab` enum 也定義於此，新增頁面要同步改它與 `MainView`。
- **Services/**：無狀態包裝，每個生態系一個（`NpmService`、`PythonService`、`BrewService`、`DatabaseService`、`AIToolService`、`GitHubToolService`、`SecurityService`、`GitHubReleaseService`），皆透過 `ShellExecutor.shared` 呼叫 CLI 並解析輸出，或呼叫 npm registry / PyPI / GitHub API。
- **ShellExecutor**：以 `/bin/zsh -c` 執行指令，自行組合 PATH（Homebrew、nvm、fnm、cargo、`~/.local/bin`），因為 GUI app 不繼承終端機 PATH。`run` 在非零結束但 stdout 有內容時仍視為成功（`npm list` 有 peer dep 警告時會非零）；`stream` 回傳 `AsyncStream` 供日誌面板即時顯示。
- **自動重新整理**：`FileSystemWatcher` 用 `DispatchSource` 監看 `/Applications`、Homebrew Cellar/Caskroom、npm global `lib/node_modules` 等目錄（2 秒 debounce）；另有每 30 分鐘 Timer。兩者都在 `isActionRunning` 時跳過，避免與進行中的操作衝突。README 提到 FSEvents，實作是 DispatchSource。
- **Models/**：`PackageItem`（npm/python/brew 共用）、`AIToolItem`、`GitHubToolItem`、`SecurityItem`、`ExecutionLog`。
- **Views/**：每個 `NavigationTab` 一個頁面；共用元件在 `Views/Components/`，視覺常數在 `Views/Theme.swift`。`StatusBarController`（Services/）管理選單列項目，內容為 `MenuBarView`。
- **Python 環境管理**：`PythonInterpreterService` 偵測系統／Homebrew／pyenv／uv 的直譯器（以 realpath 去重；沒有 Xcode 命令列工具時不碰 `/usr/bin/python3` 以免跳系統視窗），`PythonRuntime` 是同步的「目前使用的直譯器」持有者（`PythonService`、`FixCommandBuilder` 等非 async 程式碼組指令時用它），預設自動挑 3.10+ 且可寫入的版本。帶 PEP 668 `EXTERNALLY-MANAGED` 標記的直譯器只讀取、拒絕 pip 寫入。
- **漏洞修復流程**：`scanSecurityAudit` 掃描每個直譯器與每個 uv tool venv，`VulnerabilityItem.environment` 記錄所在環境；`PackageVulnerabilityGroup` 把同一套件跨環境合併成一張卡（`fixTargets` 每環境一個修復指令，失敗原因與替代方案以 `group.key(for:)` 分環境儲存）。`AppViewModel.executeFix` 修完會實際檢查已安裝版本，不信任 exit status。修不了時 `PythonEnvironmentService.plan` 用 `pip inspect` 相依圖產生「移除」或「搬到 uv tool 獨立環境」計畫（新環境全部成功才移除舊的）。uv tool 環境只升級單一套件（`uv pip install --python`），不用 `uv tool upgrade`（會重新解析整個相依樹）。
- **App 入口**：`App.swift` 強制深色（`.preferredColorScheme(.dark)`）、隱藏標題列、`.regular` activation policy。
- **自我更新檢查**：`checkSelfUpdate` 向 GitHub `liaw-boy/DevKeeper` 的最新 release 比對版本，僅提示，不會自動安裝。

## 慣例

- 介面不使用 Emoji，圖示一律 SF Symbols，遵循 Apple HIG（README 的設計要求）。
