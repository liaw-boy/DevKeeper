import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class PythonService: Sendable {
    public static let shared = PythonService()
    
    private struct PipPackageInfo: Decodable {
        let name: String
        let version: String
    }
    
    private struct PipOutdatedItem: Decodable {
        let name: String
        let version: String
        let latest_version: String
    }
    
    /// Fetches all packages that are genuinely upgradable and compatible with the current local Python runtime
    public func fetchOutdatedMap() async -> [String: String] {
        do {
            let rawJson = try await ShellExecutor.shared.run(command: "\(PythonRuntime.executable) -m pip list --outdated --format=json")
            guard let data = extractJsonData(from: rawJson) else { return [:] }
            let items = try JSONDecoder().decode([PipOutdatedItem].self, from: data)
            var map: [String: String] = [:]
            for item in items {
                map[item.name.lowercased()] = item.latest_version
            }
            return map
        } catch {
            return [:]
        }
    }
    
    public func fetchInstalledPackages() async throws -> [PackageItem] {
        let rawJson = try await ShellExecutor.shared.run(command: "\(PythonRuntime.executable) -m pip list --format=json")
        guard let data = extractJsonData(from: rawJson) else {
            return []
        }
        
        let pipItems = try JSONDecoder().decode([PipPackageInfo].self, from: data)
        var packages: [PackageItem] = []
        
        for item in pipItems {
            packages.append(PackageItem(
                name: item.name,
                currentVersion: item.version,
                type: .python,
                status: .checking
            ))
        }
        
        return packages.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    public func checkLatestVersion(for packageName: String) async -> (latestVersion: String?, description: String?, homepage: String?) {
        guard let url = URL(string: "https://pypi.org/pypi/\(packageName)/json") else {
            return (nil, nil, nil)
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        request.setValue("DevKeeper/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.devkeeperData(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return (nil, nil, nil)
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let info = json["info"] as? [String: Any] {
                let version = info["version"] as? String
                let summary = info["summary"] as? String
                let homepage = info["home_page"] as? String ?? info["project_url"] as? String
                return (version, summary, homepage)
            }
        } catch {
            // Silently handle timeout
        }
        return (nil, nil, nil)
    }
    
    public func upgradePackage(name: String) -> AsyncStream<String> {
        guard let n = InputValidator.safeName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        if let reason = PythonRuntime.writeBlockReason { return ShellExecutor.shared.rejectedStream(reason: reason) }
        let command = "\(PythonRuntime.executable) -m pip install --upgrade \(n)"
        return ShellExecutor.shared.stream(command: command)
    }
    
    public func cleanUninstallPackage(name: String) -> AsyncStream<String> {
        guard let n = InputValidator.safeName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        if let reason = PythonRuntime.writeBlockReason { return ShellExecutor.shared.rejectedStream(reason: reason) }
        let command = "\(PythonRuntime.executable) -m pip uninstall -y \(n)"
        return ShellExecutor.shared.stream(command: command)
    }
    
    public func installPackage(name: String) -> AsyncStream<String> {
        guard let n = InputValidator.safeName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        if let reason = PythonRuntime.writeBlockReason { return ShellExecutor.shared.rejectedStream(reason: reason) }
        let command = "\(PythonRuntime.executable) -m pip install \(n)"
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
