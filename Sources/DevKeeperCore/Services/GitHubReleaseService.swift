import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GitHubReleaseInfo: Codable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: String?
    public let publishedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
    }
}

public final class GitHubReleaseService: @unchecked Sendable {
    public static let shared = GitHubReleaseService()
    
    private let urlSession: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        self.urlSession = URLSession(configuration: config)
    }
    
    /// Checks latest release for a given repository (e.g. "cli/cli" or "liaw-boy/DevKeeper")
    public func fetchLatestRelease(owner: String, repo: String) async -> GitHubReleaseInfo? {
        guard InputValidator.isValidRepoComponent(owner), InputValidator.isValidRepoComponent(repo),
              let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("DevKeeper-MacApp", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await urlSession.devkeeperData(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            let decoder = JSONDecoder()
            return try decoder.decode(GitHubReleaseInfo.self, from: data)
        } catch {
            return nil
        }
    }
    
    /// Extracts `owner/repo` from a github.com URL (homepage, `git+https://...git`, `#readme` suffixes are tolerated).
    public static func githubRepo(from urlString: String?) -> (owner: String, repo: String)? {
        guard var text = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("git+") { text.removeFirst(4) }
        guard let components = URLComponents(string: text),
              let host = components.host?.lowercased(),
              host == "github.com" || host == "www.github.com" else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        var repo = parts[1]
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        guard InputValidator.isValidRepoComponent(parts[0]), InputValidator.isValidRepoComponent(repo) else { return nil }
        return (parts[0], repo)
    }
    
    /// Release notes for a specific version, trying the `v1.2.3` and `1.2.3` tag spellings.
    public func fetchReleaseNotes(owner: String, repo: String, version: String) async -> GitHubReleaseInfo? {
        let clean = version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        guard !clean.isEmpty,
              clean.range(of: #"^[0-9A-Za-z._+-]+$"#, options: .regularExpression) != nil,
              InputValidator.isValidRepoComponent(owner), InputValidator.isValidRepoComponent(repo) else { return nil }
        for tag in ["v\(clean)", clean] {
            guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/tags/\(tag)") else { continue }
            var request = URLRequest(url: url)
            request.setValue("DevKeeper-MacApp", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await urlSession.devkeeperData(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let release = try? JSONDecoder().decode(GitHubReleaseInfo.self, from: data) else { continue }
            return release
        }
        return await findRecentRelease(owner: owner, repo: repo, version: clean)
    }
    
    /// Some projects prefix tags (e.g. `rust-v0.164.0`, `jq-1.7.1`); match recent releases by the version after the prefix.
    private func findRecentRelease(owner: String, repo: String, version: String) async -> GitHubReleaseInfo? {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=50") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("DevKeeper-MacApp", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await urlSession.devkeeperData(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let releases = try? JSONDecoder().decode([GitHubReleaseInfo].self, from: data) else { return nil }
        return releases.first { Self.tagVersion($0.tagName) == version }
    }
    
    /// Version part of a tag: everything from the first digit (`rust-v0.164.0` -> `0.164.0`).
    static func tagVersion(_ tag: String) -> String? {
        guard let start = tag.firstIndex(where: { $0.isNumber }) else { return nil }
        return String(tag[start...])
    }
    
    /// Check if DevKeeper has a new version
    public func checkDevKeeperSelfUpdate(currentAppVersion: String = DevKeeperInfo.version) async -> (hasUpdate: Bool, latestVersion: String, releaseNotes: String, downloadUrl: String?) {
        guard let release = await fetchLatestRelease(owner: "liaw-boy", repo: "DevKeeper") else {
            return (false, currentAppVersion, "", nil)
        }
        
        let latestTag = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let cur = currentAppVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let hasUpdate = latestTag.compare(cur, options: .numeric) == .orderedDescending
        
        return (hasUpdate, latestTag, release.body ?? "", release.htmlUrl)
    }
}
