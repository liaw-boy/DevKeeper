import Foundation
import AppKit

public final class GitHubToolService: @unchecked Sendable {
    public static let shared = GitHubToolService()
    
    private let storageUrl: URL
    private let urlSession: URLSession
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let devKeeperFolder = appSupport.appendingPathComponent("DevKeeper", isDirectory: true)
        try? FileManager.default.createDirectory(at: devKeeperFolder, withIntermediateDirectories: true)
        self.storageUrl = devKeeperFolder.appendingPathComponent("tracked_github_tools.json")
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        self.urlSession = URLSession(configuration: config)
    }
    
    public func loadTrackedTools() -> [GitHubToolItem] {
        guard let data = try? Data(contentsOf: storageUrl),
              let items = try? JSONDecoder().decode([GitHubToolItem].self, from: data) else {
            return defaultSuggestedTools()
        }
        // Stored values are re-validated because the file can be edited outside the app.
        return items.filter {
            InputValidator.isValidRepoComponent($0.owner)
                && InputValidator.isValidRepoComponent($0.repo)
                && ($0.binaryName.isEmpty || InputValidator.isValidPackageName($0.binaryName))
        }
    }
    
    public func saveTrackedTools(_ items: [GitHubToolItem]) {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: storageUrl, options: .atomic)
        }
    }
    
    public func defaultSuggestedTools() -> [GitHubToolItem] {
        return [
            // macOS Desktop Apps (.app)
            GitHubToolItem(
                owner: "rxhanson",
                repo: "Rectangle",
                binaryName: "Rectangle",
                kind: .appBundle,
                appPath: "/Applications/Rectangle.app"
            ),
            GitHubToolItem(
                owner: "exelban",
                repo: "stats",
                binaryName: "Stats",
                kind: .appBundle,
                appPath: "/Applications/Stats.app"
            ),
            GitHubToolItem(
                owner: "iina",
                repo: "iina",
                binaryName: "IINA",
                kind: .appBundle,
                appPath: "/Applications/IINA.app"
            ),
            GitHubToolItem(
                owner: "p-mac",
                repo: "Maccy",
                binaryName: "Maccy",
                kind: .appBundle,
                appPath: "/Applications/Maccy.app"
            ),
            // CLI Tools
            GitHubToolItem(owner: "cli", repo: "cli", binaryName: "gh", kind: .cli),
            GitHubToolItem(owner: "astral-sh", repo: "uv", binaryName: "uv", kind: .cli),
            GitHubToolItem(owner: "jesseduffield", repo: "lazygit", binaryName: "lazygit", kind: .cli)
        ]
    }
    
    /// Detects if tool or app is installed locally and extracts current version
    public func detectLocalTool(item: GitHubToolItem) async -> (isInstalled: Bool, version: String, resolvedPath: String?) {
        if item.kind == .appBundle {
            return detectLocalAppBundle(item: item)
        } else {
            return await detectLocalCLI(item: item)
        }
    }
    
    /// Inspect local .app bundle (e.g. /Applications/Rectangle.app)
    private func detectLocalAppBundle(item: GitHubToolItem) -> (isInstalled: Bool, version: String, resolvedPath: String?) {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        
        var candidates: [String] = []
        if let explicitPath = item.appPath, !explicitPath.isEmpty {
            candidates.append(explicitPath)
        }
        
        let names = [item.binaryName, item.repo, item.binaryName.capitalized, item.repo.capitalized]
        for name in names {
            candidates.append("/Applications/\(name).app")
            candidates.append("\(homeDir)/Applications/\(name).app")
        }
        
        for path in candidates {
            if fileManager.fileExists(atPath: path) {
                let infoPlistPath = "\(path)/Contents/Info.plist"
                if let dict = NSDictionary(contentsOfFile: infoPlistPath) {
                    let version = (dict["CFBundleShortVersionString"] as? String) ?? (dict["CFBundleVersion"] as? String)
                    let cleanVer = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "已安裝"
                    return (true, cleanVer, path)
                }
                return (true, "已安裝", path)
            }
        }
        
        return (false, "未安裝", nil)
    }
    
    /// Inspect CLI binary in PATH
    private func detectLocalCLI(item: GitHubToolItem) async -> (isInstalled: Bool, version: String, resolvedPath: String?) {
        guard let bin = InputValidator.safeName(item.binaryName) else { return (false, "未安裝", nil) }
        do {
            let pathOutput = try await ShellExecutor.shared.run(command: "which \(bin)")
            let path = pathOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty && !path.contains("not found") {
                let quoted = InputValidator.shellQuoted(path)
                let verOutput = try? await ShellExecutor.shared.run(command: "\(quoted) --version 2>&1 || \(quoted) -v 2>&1")
                let verString = parseVersion(from: verOutput ?? "")
                return (true, verString.isEmpty ? "已安裝" : verString, path)
            }
        } catch {}
        
        return (false, "未安裝", nil)
    }
    
    /// Checks latest release from GitHub API, including direct macOS asset download links
    public func checkRemoteRelease(owner: String, repo: String) async -> (
        latestVersion: String?,
        releaseUrl: String?,
        releaseNotes: String?,
        assetDownloadUrl: String?,
        assetName: String?
    ) {
        guard InputValidator.isValidRepoComponent(owner), InputValidator.isValidRepoComponent(repo),
              let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            return (nil, nil, nil, nil, nil)
        }
        
        var request = URLRequest(url: url)
        request.setValue("DevKeeper-MacApp", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        // Include user token (stored in the Keychain) if configured
        let token = TokenStore.load()
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return (nil, nil, nil, nil, nil)
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let tag = json["tag_name"] as? String
                let htmlUrl = json["html_url"] as? String
                let body = json["body"] as? String
                
                var bestAssetUrl: String? = nil
                var bestAssetName: String? = nil
                
                if let assets = json["assets"] as? [[String: Any]] {
                    // Find macOS .dmg first, then .pkg, then .zip
                    for asset in assets {
                        guard let name = asset["name"] as? String,
                              let downloadUrl = asset["browser_download_url"] as? String else { continue }
                        let lower = name.lowercased()
                        if lower.hasSuffix(".dmg") {
                            bestAssetName = name
                            bestAssetUrl = downloadUrl
                            break
                        } else if lower.hasSuffix(".pkg") && bestAssetName == nil {
                            bestAssetName = name
                            bestAssetUrl = downloadUrl
                        } else if lower.hasSuffix(".zip") && (lower.contains("mac") || lower.contains("darwin") || lower.contains("apple")) && bestAssetName == nil {
                            bestAssetName = name
                            bestAssetUrl = downloadUrl
                        }
                    }
                    
                    // Fallback to first asset if no dmg/pkg found
                    if bestAssetUrl == nil, let first = assets.first,
                       let name = first["name"] as? String,
                       let downloadUrl = first["browser_download_url"] as? String {
                        bestAssetName = name
                        bestAssetUrl = downloadUrl
                    }
                }
                
                return (tag, htmlUrl, body, bestAssetUrl, bestAssetName)
            }
        } catch {}
        
        return (nil, nil, nil, nil, nil)
    }
    
    /// Scan /Applications for known popular open-source Mac apps and local project builds
    public func scanDiscoverableMacApps() -> [GitHubToolItem] {
        let catalog: [(owner: String, repo: String, appName: String)] = [
            ("rxhanson", "Rectangle", "Rectangle"),
            ("exelban", "stats", "Stats"),
            ("iina", "iina", "IINA"),
            ("p-mac", "Maccy", "Maccy"),
            ("lwouis", "alt-tab-macos", "AltTab"),
            ("ghostty-org", "ghostty", "Ghostty"),
            ("coteditor", "CotEditor", "CotEditor"),
            ("dwarvesf", "hidden", "Hidden Bar"),
            ("aonez", "Keka", "Keka"),
            ("mangerlahn", "latest", "Latest"),
            ("ObuchiYuki", "DevToysMac", "DevToysMac"),
            ("ollama", "ollama", "Ollama"),
            ("tailscale", "tailscale", "Tailscale")
        ]
        
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        var discovered: [GitHubToolItem] = []
        
        for item in catalog {
            let possiblePaths = [
                "/Applications/\(item.appName).app",
                "\(homeDir)/Applications/\(item.appName).app"
            ]
            
            for path in possiblePaths {
                if fileManager.fileExists(atPath: path) {
                    var tool = GitHubToolItem(
                        owner: item.owner,
                        repo: item.repo,
                        binaryName: item.appName,
                        kind: .appBundle,
                        isInstalled: true,
                        appPath: path
                    )
                    if let dict = NSDictionary(contentsOfFile: "\(path)/Contents/Info.plist"),
                       let ver = (dict["CFBundleShortVersionString"] as? String) ?? (dict["CFBundleVersion"] as? String) {
                        tool.currentVersion = ver
                    }
                    discovered.append(tool)
                    break
                }
            }
        }
        
        // Also scan the user-chosen projects folder (Settings) for apps built from local GitHub git repositories
        let projectDir = UserDefaults.standard.string(forKey: "projectsRootPath") ?? ""
        if !projectDir.isEmpty, let subdirs = try? fileManager.contentsOfDirectory(atPath: projectDir) {
            for sub in subdirs {
                let gitConfig = "\(projectDir)/\(sub)/.git/config"
                if fileManager.fileExists(atPath: gitConfig),
                   let text = try? String(contentsOfFile: gitConfig, encoding: .utf8) {
                    let pattern = #"github\.com[:/]([a-zA-Z0-9_-]+)/([a-zA-Z0-9_.-]+)"#
                    if let regex = try? NSRegularExpression(pattern: pattern) {
                        let ns = text as NSString
                        if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                            let owner = ns.substring(with: match.range(at: 1))
                            let rawRepo = ns.substring(with: match.range(at: 2))
                            let repo = rawRepo.hasSuffix(".git") ? String(rawRepo.dropLast(4)) : rawRepo
                            
                            // Check potential app names
                            let candidates = [repo, sub]
                            for c in candidates {
                                let appPath = "/Applications/\(c).app"
                                if fileManager.fileExists(atPath: appPath) {
                                    if !discovered.contains(where: { $0.owner.lowercased() == owner.lowercased() && $0.repo.lowercased() == repo.lowercased() }) {
                                        var tool = GitHubToolItem(
                                            owner: owner,
                                            repo: repo,
                                            binaryName: c,
                                            kind: .appBundle,
                                            isInstalled: true,
                                            appPath: appPath
                                        )
                                        if let dict = NSDictionary(contentsOfFile: "\(appPath)/Contents/Info.plist"),
                                           let ver = (dict["CFBundleShortVersionString"] as? String) ?? (dict["CFBundleVersion"] as? String) {
                                            tool.currentVersion = ver
                                        }
                                        discovered.append(tool)
                                    }
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return discovered
    }
    
    /// Read metadata from a user-selected .app file
    public func inspectAppBundle(at url: URL) -> (appName: String, version: String, bundleId: String?) {
        let plistUrl = url.appendingPathComponent("Contents/Info.plist")
        let appName = url.deletingPathExtension().lastPathComponent
        
        if let dict = NSDictionary(contentsOf: plistUrl) {
            let version = (dict["CFBundleShortVersionString"] as? String) ?? (dict["CFBundleVersion"] as? String) ?? "1.0.0"
            let bundleId = dict["CFBundleIdentifier"] as? String
            return (appName, version, bundleId)
        }
        
        return (appName, "1.0.0", nil)
    }
    
    private func parseVersion(from raw: String) -> String {
        let pattern = #"\b(v?[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9.]+)?)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = raw as NSString
            if let match = regex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: match.range)
            }
        }
        return raw.components(separatedBy: .whitespacesAndNewlines).first ?? ""
    }
}
