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
      version         顯示版本

    選項：
      --json          以 JSON 輸出（scan、python list、audit）
      --yes, -y       fix：直接執行替代修復（搬移或移除套件），不再詢問
      --dry-run       fix：只顯示會執行的指令，不實際執行
      --all           audit：連內建例外（系統 Python 附的 pip、setuptools、wheel）也顯示
      --projects 路徑  稽核該資料夾底下專案的 package.json 與 requirements.txt
                      （也可用環境變數 DEVKEEPER_PROJECTS）

    結束代碼：0 = 沒有待處理項目；1 = audit 發現弱點；2 = fix 後仍有無法修復的項目
    """)
}

// MARK: - Shared setup

func loadEnvironment() async -> (interpreters: [PythonInterpreter], managers: Set<PythonSource>) {
    let interpreters = await PythonInterpreterService.shared.discover()
    PythonRuntime.setCurrent(InterpreterChoice.automatic(from: interpreters))
    let managers = await PythonInterpreterService.shared.availableManagers()
    return (interpreters, managers)
}

func npmGlobals() async -> [(name: String, version: String)] {
    guard let items = try? await NpmService.shared.fetchInstalledPackages() else { return [] }
    return items.map { ($0.name, $0.currentVersion) }
}

// MARK: - Commands

struct InterpreterReport: Codable {
    let version: String
    let source: String
    let path: String
    let supported: Bool
    let managedByOS: Bool
    let externallyManaged: Bool
}

func interpreterReports(_ interpreters: [PythonInterpreter]) -> [InterpreterReport] {
    interpreters.map {
        InterpreterReport(version: $0.version, source: $0.source.rawValue, path: $0.path,
                          supported: !$0.isEndOfLife, managedByOS: $0.source == .system,
                          externallyManaged: $0.isExternallyManaged)
    }
}

func lifecycleText(_ i: PythonInterpreter) -> String {
    switch i.lifecycle {
    case .endOfLife(let d): return red("已終止支援 \(d)")
    case .endingSoon(let d): return yellow("支援至 \(d)")
    case .supported(let d): return green("支援至 \(d)")
    }
}

func commandPythonList() async -> Int32 {
    let env = await loadEnvironment()
    if options.json { printJSON(interpreterReports(env.interpreters)); return 0 }
    if env.interpreters.isEmpty { print("沒有偵測到可用的 Python。"); return 0 }
    for i in env.interpreters {
        let flags = [i.isExternallyManaged ? "受保護(PEP 668)" : nil, i.hasPip ? nil : "無 pip"].compactMap { $0 }
        print("Python \(bold(i.version))  \(i.source.rawValue)  \(lifecycleText(i))" + (flags.isEmpty ? "" : "  [\(flags.joined(separator: ", "))]"))
        print(dim("    \(i.path)"))
    }
    if let current = PythonRuntime.current { print("\nDevKeeper 使用：Python \(current.version)（\(current.source.rawValue)）") }
    return 0
}

struct ScanReport: Codable {
    let os: String
    let interpreters: [InterpreterReport]
    let npmGlobalCount: Int
    let npmOutdated: [String: String]
    let pipPythonVersion: String?
    let pipCount: Int
    let pipOutdated: [String: String]
    let systemPackageManager: String?
    let systemPackageCount: Int
    let systemUpgradable: [String]
}

func commandScan() async -> Int32 {
    let env = await loadEnvironment()
    let uname = (try? await ShellExecutor.shared.run(command: "uname -sr"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
    
    let npm = await npmGlobals()
    var npmOutdated: [String: String] = [:]
    if let out = try? await ShellExecutor.shared.run(command: "npm outdated -g --json 2>/dev/null; true"),
       let start = out.firstIndex(of: "{"), let data = String(out[start...]).data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
        for (name, info) in json { if let latest = info["latest"] as? String { npmOutdated[name] = latest } }
    }
    
    let pipItems = (try? await PythonService.shared.fetchInstalledPackages()) ?? []
    let pipOutdated = env.interpreters.isEmpty ? [:] : await PythonService.shared.fetchOutdatedMap()
    
    var manager: String?
    var systemCount = 0
    var upgradable: [String] = []
    #if os(Linux)
    if await AptService.shared.isAvailable() {
        manager = "apt"
        systemCount = await AptService.shared.installedCount()
        upgradable = await AptService.shared.upgradable().map { "\($0.name) \($0.currentVersion) → \($0.newVersion)" }
    }
    #else
    if let out = try? await ShellExecutor.shared.run(command: "command -v brew >/dev/null 2>&1 && brew outdated --quiet; true") {
        manager = "Homebrew"
        upgradable = out.split(separator: "\n").map(String.init)
    }
    #endif
    
    let report = ScanReport(
        os: uname, interpreters: interpreterReports(env.interpreters),
        npmGlobalCount: npm.count, npmOutdated: npmOutdated,
        pipPythonVersion: PythonRuntime.current?.version, pipCount: pipItems.count, pipOutdated: pipOutdated,
        systemPackageManager: manager, systemPackageCount: systemCount, systemUpgradable: upgradable
    )
    if options.json { printJSON(report); return 0 }
    
    print(bold("系統：") + uname)
    print(bold("\nPython：") + "\(env.interpreters.count) 個版本")
    for i in env.interpreters { print("  \(i.version)  \(i.source.rawValue)  \(lifecycleText(i))") }
    print(bold("\nnpm 全域套件：") + "\(npm.count) 個，\(npmOutdated.count) 個可升級")
    for (name, latest) in npmOutdated.sorted(by: { $0.key < $1.key }) { print("  \(name) → \(latest)") }
    if let v = PythonRuntime.current?.version {
        print(bold("\npip 套件（Python \(v)）：") + "\(pipItems.count) 個，\(pipOutdated.count) 個可升級")
        for (name, latest) in pipOutdated.sorted(by: { $0.key < $1.key }) { print("  \(name) → \(latest)") }
    }
    if let manager {
        print(bold("\n系統套件（\(manager)）：") + (systemCount > 0 ? "\(systemCount) 個已安裝，" : "") + "\(upgradable.count) 個可升級")
        for line in upgradable.prefix(20) { print("  \(line)") }
        if upgradable.count > 20 { print(dim("  …另有 \(upgradable.count - 20) 個")) }
    }
    return 0
}

struct AuditItemReport: Codable {
    let package: String
    let ecosystem: String
    let environments: [String]
    let severity: String
    let currentVersion: String
    let safeVersion: String?
    let cves: [String]
    let fixCommands: [String]
}

func auditGroups(_ env: (interpreters: [PythonInterpreter], managers: Set<PythonSource>)) async -> (groups: [PackageVulnerabilityGroup], hidden: Int) {
    let items = await AuditEngine.audit(
        interpreters: env.interpreters,
        npmPackages: await npmGlobals(),
        projectsRoot: options.projects
    )
    let visible = options.showAll ? items : items.filter { !AuditEngine.isBuiltInException($0, interpreters: env.interpreters) }
    return (PackageVulnerabilityGroup.grouped(from: visible), items.count - visible.count)
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
    if options.json {
        printJSON(result.groups.map {
            AuditItemReport(package: $0.packageName, ecosystem: $0.ecosystem, environments: $0.fixTargets.map { $0.environment?.label ?? "global" },
                            severity: $0.highestSeverity.rawValue, currentVersion: $0.currentVersion, safeVersion: $0.targetSafeVersion,
                            cves: $0.cveList, fixCommands: $0.fixCommands)
        })
        return result.groups.isEmpty ? 0 : 1
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
    return 1
}

func commandFix() async -> Int32 {
    let env = await loadEnvironment()
    let result = await auditGroups(env)
    guard !result.groups.isEmpty else { print(green("沒有需要修復的項目。")); return 0 }
    
    let noopSink: LogSink = { _ in }
    var failed: [(group: PackageVulnerabilityGroup, env: PythonEnvironmentRef?, reason: String)] = []
    var fixedCount = 0
    
    for group in result.groups {
        for target in group.fixTargets {
            let place = target.environment?.label ?? "全域"
            guard !target.command.isEmpty else {
                failed.append((group, target.environment, "這個環境無法自動修復"))
                continue
            }
            if options.dryRun {
                print("[dry-run] \(group.packageName)（\(place)）：\(target.command)")
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
    if options.dryRun { return 0 }
    print(bold("\n直接升級：成功 \(fixedCount) 項，失敗 \(failed.count) 項"))
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
case "help": usage()
default:
    printErr("未知的指令：\(command)\n")
    usage()
    exitCode = 64
}
exit(exitCode)
