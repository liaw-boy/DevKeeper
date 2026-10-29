import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class PythonService: Sendable {
    public static let shared = PythonService()
    
    private struct PipPackageInfo: Decodable {
        let name: String
        let version: String
        let location: String?
    }
    
    private struct PipOutdatedItem: Decodable {
        let name: String
        let version: String
        let latest_version: String
        let location: String?
    }
    
    /// Fetches all packages that are genuinely upgradable and compatible with the current local Python runtime
    public func fetchOutdatedMap() async -> [String: String] {
        do {
            let rawJson = try await ShellExecutor.shared.run(command: "\(PythonRuntime.executable) -m pip list --outdated -v --format=json")
            guard let data = extractJsonData(from: rawJson) else { return [:] }
            let items = try JSONDecoder().decode([PipOutdatedItem].self, from: data)
            var map: [String: String] = [:]
            for item in items where !PythonEnvironmentService.isOSManagedLocation(item.location) {
                map[item.name.lowercased()] = item.latest_version
            }
            return map
        } catch {
            return [:]
        }
    }
    
    public func fetchInstalledPackages() async throws -> [PackageItem] {
        let rawJson = try await ShellExecutor.shared.run(command: "\(PythonRuntime.executable) -m pip list -v --format=json")
        guard let data = extractJsonData(from: rawJson) else {
            return []
        }
        
        // Packages owned by the OS (apt, Xcode) must not be upgraded with pip, so they are not listed.
        let pipItems = try JSONDecoder().decode([PipPackageInfo].self, from: data)
            .filter { !PythonEnvironmentService.isOSManagedLocation($0.location) }
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
    
    /// Fields shown for a package, read from its PyPI page.
    public struct PyPIInfo: Codable, Equatable, Sendable {
        public var version: String?
        public var summary: String?
        public var homepage: String?
    }
    
    /// Reads `info` from a PyPI JSON response. Text comes from a third party, so it is trimmed and capped, and
    /// only https links are kept.
    public static func parsePyPIInfo(_ data: Data) -> PyPIInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["info"] as? [String: Any] else { return nil }
        func text(_ value: Any?, limit: Int) -> String? {
            guard let raw = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            return String(raw.prefix(limit))
        }
        func link(_ value: Any?) -> String? {
            guard let raw = text(value, limit: 300), let url = URL(string: raw), url.scheme == "https" else { return nil }
            return raw
        }
        var homepage: String?
        if let urls = info["project_urls"] as? [String: Any] {
            for key in ["Homepage", "Home", "Source", "Source Code", "Repository", "GitHub"] {
                if let found = link(urls[key]) { homepage = found; break }
            }
        }
        homepage = homepage ?? link(info["home_page"]) ?? link(info["project_url"])
        return PyPIInfo(version: text(info["version"], limit: 64), summary: text(info["summary"], limit: 300), homepage: homepage)
    }
    
    public func fetchPyPIInfo(for packageName: String) async -> PyPIInfo? {
        guard InputValidator.isValidPackageName(packageName),
              let url = URL(string: "https://pypi.org/pypi/\(packageName)/json") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        request.setValue("DevKeeper/\(DevKeeperInfo.version)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.devkeeperData(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return Self.parsePyPIInfo(data)
    }
    
    /// Looks up several packages with a small amount of concurrency. Packages that could not be reached are
    /// left out, so callers can try them again next time.
    public func fetchPyPIInfo(for names: [String]) async -> [String: PyPIInfo] {
        var result: [String: PyPIInfo] = [:]
        var index = 0
        let batchSize = 8
        while index < names.count {
            let batch = Array(names[index..<min(index + batchSize, names.count)])
            index += batchSize
            await withTaskGroup(of: (String, PyPIInfo?).self) { group in
                for name in batch {
                    group.addTask { (name, await self.fetchPyPIInfo(for: name)) }
                }
                for await (name, info) in group {
                    if let info { result[name] = info }
                }
            }
        }
        return result
    }
    
    public func checkLatestVersion(for packageName: String) async -> (latestVersion: String?, description: String?, homepage: String?) {
        guard let info = await fetchPyPIInfo(for: packageName) else { return (nil, nil, nil) }
        return (info.version, info.summary, info.homepage)
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
