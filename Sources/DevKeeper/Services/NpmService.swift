import Foundation

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
    
    public func checkLatestVersion(for packageName: String) async -> (latestVersion: String?, description: String?, homepage: String?) {
        guard let encodedName = packageName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://registry.npmjs.org/\(encodedName)/latest") else {
            return (nil, nil, nil)
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        request.setValue("DevKeeper/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return (nil, nil, nil)
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let version = json["version"] as? String
                let desc = json["description"] as? String
                let homepage = json["homepage"] as? String
                return (version, desc, homepage)
            }
        } catch {
            // Silently handle network timeout
        }
        return (nil, nil, nil)
    }
    
    public func upgradePackage(name: String) -> AsyncStream<String> {
        guard let n = InputValidator.safeName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        let command = "npm install -g \(n)@latest"
        return ShellExecutor.shared.stream(command: command)
    }
    
    public func upgradeAll(packages: [String]) -> AsyncStream<String> {
        guard packages.allSatisfy(InputValidator.isValidPackageName) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        let command = "npm install -g " + packages.map { "\($0)@latest" }.joined(separator: " ")
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
