import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class NpmService: Sendable {
    public static let shared = NpmService()
    
    private struct NpmListResponse: Decodable {
        let dependencies: [String: NpmDependency]?
    }
    
    private struct NpmDependency: Decodable {
        let version: String?
    }
    
    public func fetchInstalledPackages() async throws -> [PackageItem] {
        let rawJson = try await ShellExecutor.shared.run(command: "npm list -g --depth=0 --json")
        guard let data = extractJsonData(from: rawJson) else {
            return []
        }
        
        let response = try JSONDecoder().decode(NpmListResponse.self, from: data)
        guard let deps = response.dependencies else { return [] }
        
        var packages: [PackageItem] = []
        for (name, dep) in deps {
            let version = dep.version ?? "Unknown"
            packages.append(PackageItem(
                name: name,
                currentVersion: version,
                type: .npm,
                status: .checking
            ))
        }
        
        return packages.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    /// Fields shown for a package, read from the npm registry.
    public struct RegistryInfo: Equatable, Sendable {
        public var version: String?
        public var description: String?
        public var homepage: String?
    }
    
    /// A browsable https link from a `repository` field: `git+https://host/user/repo.git`, `git://...`,
    /// `github:user/repo` or `user/repo` (npm's GitHub shorthand). Anything else yields nil.
    public static func repositoryLink(_ value: Any?) -> String? {
        let raw: String?
        if let text = value as? String { raw = text } else { raw = (value as? [String: Any])?["url"] as? String }
        guard var url = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty, url.count <= 300 else { return nil }
        if url.hasPrefix("github:") { url = "https://github.com/" + url.dropFirst("github:".count) }
        else if url.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil { url = "https://github.com/" + url }
        url = url.replacingOccurrences(of: "git+", with: "")
        if url.hasPrefix("git://") { url = "https://" + url.dropFirst("git://".count) }
        if url.hasPrefix("ssh://git@") { url = "https://" + url.dropFirst("ssh://git@".count) }
        if url.hasSuffix(".git") { url = String(url.dropLast(4)) }
        guard let parsed = URL(string: url), parsed.scheme == "https", parsed.host?.isEmpty == false else { return nil }
        return url
    }
    
    /// Reads the registry's `latest` document. Text is third-party, so it is trimmed and capped, and only https
    /// links are kept.
    public static func parseRegistryInfo(_ data: Data) -> RegistryInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func text(_ value: Any?, limit: Int) -> String? {
            guard let raw = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            return String(raw.prefix(limit))
        }
        var homepage: String?
        if let raw = text(json["homepage"], limit: 300), let url = URL(string: raw), url.scheme == "https" { homepage = raw }
        homepage = homepage ?? repositoryLink(json["repository"])
        return RegistryInfo(version: text(json["version"], limit: 64), description: text(json["description"], limit: 300), homepage: homepage)
    }
    
    public func checkLatestVersion(for packageName: String) async -> (latestVersion: String?, description: String?, homepage: String?) {
        guard let encodedName = packageName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://registry.npmjs.org/\(encodedName)/latest") else {
            return (nil, nil, nil)
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        request.setValue("DevKeeper/\(DevKeeperInfo.version)", forHTTPHeaderField: "User-Agent")
        
        guard let (data, response) = try? await URLSession.shared.devkeeperData(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let info = Self.parseRegistryInfo(data) else { return (nil, nil, nil) }
        return (info.version, info.description, info.homepage)
    }
    
    public func upgradePackage(name: String) -> AsyncStream<String> {
        guard let n = InputValidator.safeName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        let command = "npm install -g \(n)@latest"
        return ShellExecutor.shared.stream(command: command)
    }
    
    /// The command that upgrades the listed global packages, or nil when a name is not allowed.
    public static func upgradeAllCommand(packages: [String]) -> String? {
        guard !packages.isEmpty, packages.allSatisfy(InputValidator.isValidPackageName) else { return nil }
        return "npm install -g " + packages.map { "\($0)@latest" }.joined(separator: " ")
    }
    
    public func upgradeAll(packages: [String]) -> AsyncStream<String> {
        guard let command = Self.upgradeAllCommand(packages: packages) else {
            return ShellExecutor.shared.rejectedStream(reason: "沒有可升級的項目，或套件名稱含不允許的字元")
        }
        return ShellExecutor.shared.stream(command: command)
    }
    
    public func installPackage(name: String) -> AsyncStream<String> {
        guard let n = InputValidator.safeName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        let command = "npm install -g \(n)"
        return ShellExecutor.shared.stream(command: command)
    }
    
    public func cleanUninstallPackage(name: String) -> AsyncStream<String> {
        guard let n = InputValidator.safeName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        let command = "npm uninstall -g \(n)"
        return ShellExecutor.shared.stream(command: command)
    }
    
    private func extractJsonData(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        let jsonSubstring = text[start...end]
        return jsonSubstring.data(using: .utf8)
    }
}
