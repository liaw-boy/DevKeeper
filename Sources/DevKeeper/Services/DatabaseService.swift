import Foundation

public final class DatabaseService: Sendable {
    public static let shared = DatabaseService()
    
    // Known common database formulae
    public static let commonDatabases = [
        "postgresql@16": "PostgreSQL 16 關聯式資料庫",
        "mysql": "MySQL 關聯式資料庫",
        "redis": "Redis 高速記憶體快取與鍵值資料庫",
        "mongodb-community": "MongoDB 現代 NoSQL 文件資料庫",
        "mariadb": "MariaDB 社群維護關聯式資料庫",
        "sqlite": "SQLite 輕量級嵌入式資料庫"
    ]
    
    private struct BrewServiceEntry: Decodable {
        let name: String
        let status: String
        let user: String?
        let file: String?
    }
    
    public func fetchServices() async throws -> [DatabaseServiceItem] {
        var runningServicesMap: [String: BrewServiceEntry] = [:]
        
        do {
            let rawJson = try await ShellExecutor.shared.run(command: "brew services list --json")
            if let data = extractJsonData(from: rawJson) {
                let entries = try JSONDecoder().decode([BrewServiceEntry].self, from: data)
                for entry in entries {
                    runningServicesMap[entry.name] = entry
                }
            }
        } catch {
            // Ignore error if brew services has no output
        }
        
        // Also check which database formulae are installed via brew list
        let installedFormulaeRaw = (try? await ShellExecutor.shared.run(command: "brew list --formula")) ?? ""
        let installedSet = Set(installedFormulaeRaw.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) })
        
        var results: [DatabaseServiceItem] = []
        
        // 1. Add any service currently listed in brew services
        for (name, entry) in runningServicesMap {
            let status: ServiceStatus
            switch entry.status.lowercased() {
            case "started": status = .started
            case "stopped": status = .stopped
            case "error": status = .error
            default: status = .unknown
            }
            results.append(DatabaseServiceItem(
                name: name,
                status: status,
                user: entry.user,
                file: entry.file
            ))
        }
        
        // 2. Add common databases that are installed but maybe not started
        for (dbName, _) in DatabaseService.commonDatabases {
            if installedSet.contains(dbName) && !results.contains(where: { $0.name == dbName }) {
                results.append(DatabaseServiceItem(
                    name: dbName,
                    status: .stopped
                ))
            }
        }
        
        return results.sorted { $0.name < $1.name }
    }
    
    public func startService(name: String) -> AsyncStream<String> {
        guard let n = InputValidator.safeName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        let command = "brew services start \(n)"
        return ShellExecutor.shared.stream(command: command)
    }
    
    public func stopService(name: String) -> AsyncStream<String> {
        guard let n = InputValidator.safeName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        let command = "brew services stop \(n)"
        return ShellExecutor.shared.stream(command: command)
    }
    
    public func restartService(name: String) -> AsyncStream<String> {
        guard let n = InputValidator.safeName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        let command = "brew services restart \(n)"
        return ShellExecutor.shared.stream(command: command)
    }
    
    public func installDatabase(name: String) -> AsyncStream<String> {
        guard let n = InputValidator.safeName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        let command: String
        if n.contains("mongo") {
            command = "brew tap mongodb/brew && brew install \(n)"
        } else {
            command = "brew install \(n)"
        }
        return ShellExecutor.shared.stream(command: command)
    }
    
    public func cleanUninstallDatabase(name: String) -> AsyncStream<String> {
        // Stop service first, then uninstall and autoremove
        guard let n = InputValidator.safeName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        let command = "brew services stop \(n) ; brew uninstall \(n) && brew autoremove"
        return ShellExecutor.shared.stream(command: command)
    }
    
    private func extractJsonData(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]") else {
            return nil
        }
        let jsonSubstring = text[start...end]
        return jsonSubstring.data(using: .utf8)
    }
}
