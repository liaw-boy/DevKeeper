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

public struct TrackedGitHubRepo: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(owner)/\(repo)" }
    public let owner: String
    public let repo: String
    public var currentVersion: String
    public var latestVersion: String?
    public var htmlUrl: String?
    public var releaseNotes: String?
    
    public init(owner: String, repo: String, currentVersion: String, latestVersion: String? = nil, htmlUrl: String? = nil, releaseNotes: String? = nil) {
        self.owner = owner
        self.repo = repo
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.htmlUrl = htmlUrl
        self.releaseNotes = releaseNotes
    }
    
    public var isOutdated: Bool {
        guard let latest = latestVersion, !latest.isEmpty else { return false }
        let cleanCurrent = currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let cleanLatest = latest.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        return cleanCurrent != cleanLatest && cleanCurrent.compare(cleanLatest, options: .numeric) == .orderedAscending
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
    
    /// Check if DevKeeper has a new version
    public func checkDevKeeperSelfUpdate(currentAppVersion: String = "1.0.0") async -> (hasUpdate: Bool, latestVersion: String, releaseNotes: String, downloadUrl: String?) {
        guard let release = await fetchLatestRelease(owner: "liaw-boy", repo: "DevKeeper") else {
            return (false, currentAppVersion, "", nil)
        }
        
        let latestTag = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let cur = currentAppVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let hasUpdate = latestTag.compare(cur, options: .numeric) == .orderedDescending
        
        return (hasUpdate, latestTag, release.body ?? "", release.htmlUrl)
    }
}
