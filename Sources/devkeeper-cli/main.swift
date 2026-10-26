import Foundation
import DevKeeperCore

// MARK: - Output helpers

let useColor = isatty(STDOUT_FILENO) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
func paint(_ text: String, _ code: String) -> String { useColor ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text }
func bold(_ s: String) -> String { paint(s, "1") }
func red(_ s: String) -> String { paint(s, "31") }
func green(_ s: String) -> String { paint(s, "32") }
func yellow(_ s: String) -> String { paint(s, "33") }
func dim(_ s: String) -> String { paint(s, "2") }

func printErr(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) { print(text) }
}

// MARK: - Arguments

struct Options {
    var json = false
    var yes = false
    var dryRun = false
    var showAll = false
    var port: UInt16 = 8765
    var projects: String? = ProcessInfo.processInfo.environment["DEVKEEPER_PROJECTS"]
}

func parseArguments() -> (Options, [String]) {
    let args = Array(CommandLine.arguments.dropFirst())
    var options = Options()
    var positional: [String] = []
    var index = 0
    while index < args.count {
        let a = args[index]
        switch a {
        case "--json": options.json = true
        case "--yes", "-y": options.yes = true
        case "--dry-run": options.dryRun = true
        case "--all": options.showAll = true
        case "--projects":
            index += 1
            if index < args.count { options.projects = args[index] }
        case "--port":
            index += 1
            if index < args.count, let value = UInt16(args[index]) { options.port = value } else { printErr("--port 需要 0–65535 的數字"); exit(64) }
        case "-h", "--help": positional = ["help"]
        default: positional.append(a)
        }
        index += 1
    }
    return (options, positional)
}

let (options, positional) = parseArguments()

func usage() {
    print("""
    \(bold("devkeeper-cli")) \(DevKeeperInfo.version) — 開發環境套件與安全弱點管理（命令列版）

    用法：devkeeper-cli <指令> [選項]

    指令：
      scan            列出 Python 版本、npm 與 pip 套件、系統套件的待升級狀態
      python list     列出所有偵測到的 Python 與支援狀態
      audit           稽核所有 Python 環境、uv tool 與 npm 的已知安全弱點（OSV）
      fix             修復弱點：先嘗試直接升級，修不了時規劃「搬到 uv 獨立環境」或「移除」
      serve           啟動本機網頁介面（僅限 127.0.0.1，唯讀），網址含一次性金鑰
      version         顯示版本

    選項：
      --json          以 JSON 輸出（scan、python list、audit）
      --yes, -y       fix：確認執行（升級、搬移或移除套件）；沒加時只預覽
      --dry-run       fix：只預覽會執行的指令（與不加 --yes 相同，結束代碼為 0）
      --all           audit：連內建例外（系統 Python 附的 pip、setuptools、wheel）也顯示
      --port 埠號      serve：監聽的連接埠（預設 8765，0 = 自動挑選）
      --projects 路徑  稽核該資料夾底下專案的 package.json 與 requirements.txt
                      （也可用環境變數 DEVKEEPER_PROJECTS）

    結束代碼：0 = 沒有待處理項目；1 = audit 發現弱點；2 = fix 後仍有無法修復的項目；
    3 = 稽核查詢失敗，結果不完整（audit、fix）
    """)
}

// MARK: - Shared setup

func loadEnvironment() async -> DetectedEnvironment { await ReportBuilder.loadEnvironment() }

// MARK: - Commands

func lifecycleText(_ i: PythonInterpreter) -> String {
    switch i.lifecycle {
    case .endOfLife(let d): return red("已終止支援 \(d)")
    case .endingSoon(let d): return yellow("支援至 \(d)")
    case .supported(let d): return green("支援至 \(d)")
    }
}

func commandPythonList() async -> Int32 {
    let env = await loadEnvironment()
    if options.json { printJSON(ReportBuilder.interpreterReports(env.interpreters)); return 0 }
    if env.interpreters.isEmpty { print("沒有偵測到可用的 Python。"); return 0 }
    for i in env.interpreters {
        let flags = [i.isExternallyManaged ? "受保護(PEP 668)" : nil, i.hasPip ? nil : "無 pip"].compactMap { $0 }
        print("Python \(bold(i.version))  \(i.source.rawValue)  \(lifecycleText(i))" + (flags.isEmpty ? "" : "  [\(flags.joined(separator: ", "))]"))
        print(dim("    \(i.path)"))
    }
    if let current = PythonRuntime.current { print("\nDevKeeper 使用：Python \(current.version)（\(current.source.rawValue)）") }
    return 0
}

func commandScan() async -> Int32 {
    let env = await loadEnvironment()
    let report = await ReportBuilder.scan(env)
    let npmOutdated = report.npmOutdated, pipOutdated = report.pipOutdated
    let manager = report.systemPackageManager, systemCount = report.systemPackageCount, upgradable = report.systemUpgradable
    let uname = report.os
    if options.json { printJSON(report); return 0 }
    
    print(bold("系統：") + uname)
    print(bold("\nPython：") + "\(env.interpreters.count) 個版本")
    for i in env.interpreters { print("  \(i.version)  \(i.source.rawValue)  \(lifecycleText(i))") }
    print(bold("\nnpm 全域套件：") + "\(report.npmGlobalCount) 個，\(npmOutdated.count) 個可升級")
    for (name, latest) in npmOutdated.sorted(by: { $0.key < $1.key }) { print("  \(name) → \(latest)") }
    if let v = PythonRuntime.current?.version {
        print(bold("\npip 套件（Python \(v)）：") + "\(report.pipCount) 個，\(pipOutdated.count) 個可升級")
        for (name, latest) in pipOutdated.sorted(by: { $0.key < $1.key }) { print("  \(name) → \(latest)") }
    }
    if let manager {
        print(bold("\n系統套件（\(manager)）：") + (systemCount > 0 ? "\(systemCount) 個已安裝，" : "") + "\(upgradable.count) 個可升級")
        for line in upgradable.prefix(20) { print("  \(line)") }
        if upgradable.count > 20 { print(dim("  …另有 \(upgradable.count - 20) 個")) }
    }
    return 0
}

func auditGroups(_ env: DetectedEnvironment) async -> (groups: [PackageVulnerabilityGroup], hidden: Int, failed: Int) {
    await ReportBuilder.auditGroups(env, projectsRoot: options.projects, showAll: options.showAll)
}

func severityText(_ s: VulnerabilitySeverity) -> String {
    switch s {
    case .critical: return red("嚴重")
    case .high: return red("高")
    case .medium: return yellow("中")
    case .low: return "低"
    case .unknown: return "未知"
    }
}

func commandAudit() async -> Int32 {
    let env = await loadEnvironment()
    let result = await auditGroups(env)
    let incompleteNote = "有 \(result.failed) 個套件查詢 OSV 失敗，結果不完整，請確認網路後重試。"
    if options.json {
        printJSON(ReportBuilder.auditItems(result.groups))
        if result.failed > 0 { FileHandle.standardError.write(Data((incompleteNote + "\n").utf8)) }
        return result.groups.isEmpty ? (result.failed > 0 ? 3 : 0) : 1
    }
    if result.groups.isEmpty && result.failed > 0 {
        print(yellow("無法確認是否有弱點。") + incompleteNote)
        return 3
    }
    if result.groups.isEmpty {
        print(green("沒有發現需要處理的已知安全弱點。") + (result.hidden > 0 ? dim("（已隱藏 \(result.hidden) 項內建例外，--all 可顯示）") : ""))
        return 0
    }
    let cveTotal = result.groups.reduce(0) { $0 + $1.cveList.count }
    print(bold("\(result.groups.count) 個套件存在弱點，共 \(cveTotal) 個 CVE\n"))
    for g in result.groups {
        let where_ = g.fixTargets.map { $0.environment?.label ?? "全域" }.joined(separator: "、")
        print("[\(severityText(g.highestSeverity))] \(bold(g.packageName))  \(dim(where_))")
        print("    版本 \(g.currentVersion)" + (g.targetSafeVersion.map { " → 安全版本 \($0)" } ?? ""))
        print("    " + g.cveList.prefix(3).joined(separator: "、") + (g.cveList.count > 3 ? " 等 \(g.cveList.count) 個" : ""))
    }
    if result.hidden > 0 { print(dim("\n已隱藏 \(result.hidden) 項內建例外（--all 可顯示）")) }
    if result.failed > 0 { print(yellow("\n注意：") + incompleteNote) }
    return 1
}

func commandFix() async -> Int32 {
    let env = await loadEnvironment()
    let result = await auditGroups(env)
    guard !result.groups.isEmpty else {
        if result.failed > 0 {
            print(yellow("無法確認是否有弱點：") + "有 \(result.failed) 個套件查詢 OSV 失敗，請確認網路後重試。")
            return 3
        }
        print(green("沒有需要修復的項目。"))
        return 0
    }
    
    let noopSink: LogSink = { _ in }
    // Nothing is changed without --yes: upgrades can break other packages, so the plan is shown first.
    let preview = options.dryRun || !options.yes
    var failed: [(group: PackageVulnerabilityGroup, env: PythonEnvironmentRef?, reason: String)] = []
    var fixedCount = 0
    
    for group in result.groups {
        for target in group.fixTargets {
            let place = target.environment?.label ?? "全域"
            guard !target.command.isEmpty else {
                failed.append((group, target.environment, "這個環境無法自動修復"))
                continue
            }
            if preview {
                print("[預覽] \(group.packageName)（\(place)）：\(target.command)")
                continue
            }
            print("修復 \(bold(group.packageName))（\(place)）…")
            let outcome = await FixEngine.execute(
                command: target.command, packageName: group.packageName, ecosystem: group.ecosystem,
                targetVersion: group.targetSafeVersion, environment: target.environment,
                interpreters: env.interpreters, output: noopSink, notice: { printErr(dim("    " + $0)) }
            )
            switch outcome {
            case .fixed:
                fixedCount += 1
                print("    " + green("已修復"))
            case .failed(let reason):
                failed.append((group, target.environment, reason))
                print("    " + red("無法直接修復：") + reason)
            }
        }
    }
    if preview {
        print(dim("\n升級後若讓其他套件的版本限制不成立，會自動還原為原本的版本。直接升級失敗時，可能會再提出搬移或移除的替代做法。"))
        if !options.dryRun { print(dim("確認後加上 --yes 執行：devkeeper-cli fix --yes")) }
        return options.dryRun ? 0 : 2
    }
    print(bold("\n直接升級：成功 \(fixedCount) 項，失敗 \(failed.count) 項"))
    if let url = FixHistory.defaultURL { print(dim("升級前後的版本已記錄在 \(url.path)")) }
    guard !failed.isEmpty else { return 0 }
    
    // Alternative fixes for what could not be upgraded in place.
    var plans: [RemediationPlan] = []
    var seen = Set<String>()
    var unresolved = 0
    for item in failed {
        guard let envRef = item.env, envRef.kind == .interpreter,
              let interpreter = env.interpreters.first(where: { $0.path == envRef.pythonPath }) else { unresolved += 1; continue }
        let uv = env.managers.contains(.uv)
        switch await PythonEnvironmentService.shared.plan(
            packageName: item.group.packageName, interpreter: interpreter,
            targetPython: InterpreterChoice.migrationTarget(from: env.interpreters, uvAvailable: uv), uvAvailable: uv
        ) {
        case .plan(let plan):
            let signature = "\(plan.kind)|\(plan.interpreterPath)|\(plan.toolsToInstall)|\(plan.packagesToRemove)"
            if seen.insert(signature).inserted { plans.append(plan) }
        case .unavailable(let why):
            unresolved += 1
            print(yellow("  \(item.group.packageName)：") + why)
        }
    }
    guard !plans.isEmpty else { return unresolved > 0 ? 2 : 0 }
    
    print(bold("\n替代修復（可處理其餘項目）："))
    for plan in plans {
        print("  • \(plan.kind == .migrate ? "搬到獨立環境" : "移除套件")（為了修復 \(plan.packageName)）")
        for line in plan.summaryLines { print("      \(line)") }
    }
    guard options.yes else {
        print(dim("\n這些操作會安裝或移除套件。確認後加上 --yes 執行：devkeeper-cli fix --yes"))
        return 2
    }
    
    var removed = Set<String>()
    var planFailures = 0
    for plan in plans {
        let names = Set(plan.packagesToRemove.map { PythonDependencyGraph.normalize($0) })
        if names.isSubset(of: removed) { continue }
        print("\n執行：\(plan.packageName)")
        let outcome = await RemediationEngine.execute(
            plan, interpreters: env.interpreters,
            stage: { print("    \($0)") }, output: noopSink, notice: { print(dim("    " + $0)) }
        )
        switch outcome {
        case .success:
            removed.formUnion(names)
            print("    " + green("完成"))
        case .failure(let reason):
            planFailures += 1
            print("    " + red("失敗：") + reason)
        }
    }
    return (planFailures + unresolved) > 0 ? 2 : 0
}

func commandServe() async -> Int32 {
    let server: LocalHTTPServer
    do { server = try LocalHTTPServer(port: options.port) } catch {
        printErr(red("無法啟動：") + "\(error)")
        return 1
    }
    let token = RequestGuard.makeToken()
    let app = WebApp(token: token, port: server.port, projectsRoot: options.projects)
    server.start { await app.handle($0) }
    print(bold("DevKeeper 網頁介面已啟動") + dim("（僅限本機，唯讀）"))
    print("  http://127.0.0.1:\(server.port)/?token=\(token)")
    print(dim("\n用瀏覽器開啟上面的網址；按 Ctrl+C 結束。金鑰每次啟動都會重新產生。"))
    fflush(stdout)
    while true { try? await Task.sleep(nanoseconds: 3_600_000_000_000) }
}

// MARK: - Dispatch

let command = positional.first ?? "help"
let sub = positional.dropFirst().first
var exitCode: Int32 = 0
switch command {
case "version", "--version": print("devkeeper-cli \(DevKeeperInfo.version)")
case "scan": exitCode = await commandScan()
case "python":
    if sub == "list" { exitCode = await commandPythonList() } else { usage(); exitCode = 64 }
case "audit": exitCode = await commandAudit()
case "fix": exitCode = await commandFix()
case "serve": exitCode = await commandServe()
case "help": usage()
default:
    printErr("未知的指令：\(command)\n")
    usage()
    exitCode = 64
}
exit(exitCode)
