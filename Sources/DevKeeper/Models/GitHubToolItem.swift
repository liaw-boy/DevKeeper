import Foundation
import AppKit

public enum GitHubToolKind: String, Codable, Sendable, CaseIterable {
    case appBundle = "macOS 桌面應用 (.app)"
    case cli = "CLI 命令列工具"
}

public struct GitHubToolItem: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(owner)/\(repo)" }
    public let owner: String
    public let repo: String
    public var binaryName: String
    public var kind: GitHubToolKind
    public var currentVersion: String
    public var latestVersion: String?
    public var htmlUrl: String?
    public var releaseNotes: String?
    public var isInstalled: Bool
    public var binaryPath: String?
    public var appPath: String?
    public var assetDownloadUrl: String?
    public var assetName: String?
    public var lastChecked: Date?
    
    public init(
        owner: String,
        repo: String,
        binaryName: String? = nil,
        kind: GitHubToolKind = .cli,
        currentVersion: String = "未檢測",
        latestVersion: String? = nil,
        htmlUrl: String? = nil,
        releaseNotes: String? = nil,
        isInstalled: Bool = false,
        binaryPath: String? = nil,
        appPath: String? = nil,
        assetDownloadUrl: String? = nil,
        assetName: String? = nil,
        lastChecked: Date? = nil
    ) {
        self.owner = owner
        self.repo = repo
        self.binaryName = binaryName ?? repo
        self.kind = kind
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.htmlUrl = htmlUrl
        self.releaseNotes = releaseNotes
        self.isInstalled = isInstalled
        self.binaryPath = binaryPath
        self.appPath = appPath
        self.assetDownloadUrl = assetDownloadUrl
        self.assetName = assetName
        self.lastChecked = lastChecked
    }
    
    enum CodingKeys: String, CodingKey {
        case owner, repo, binaryName, kind, currentVersion, latestVersion
        case htmlUrl, releaseNotes, isInstalled, binaryPath, appPath
        case assetDownloadUrl, assetName, lastChecked
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.owner = try container.decode(String.self, forKey: .owner)
        self.repo = try container.decode(String.self, forKey: .repo)
        self.binaryName = try container.decodeIfPresent(String.self, forKey: .binaryName) ?? repo
        self.kind = try container.decodeIfPresent(GitHubToolKind.self, forKey: .kind) ?? .cli
        self.currentVersion = try container.decodeIfPresent(String.self, forKey: .currentVersion) ?? "未檢測"
        self.latestVersion = try container.decodeIfPresent(String.self, forKey: .latestVersion)
        self.htmlUrl = try container.decodeIfPresent(String.self, forKey: .htmlUrl)
        self.releaseNotes = try container.decodeIfPresent(String.self, forKey: .releaseNotes)
        self.isInstalled = try container.decodeIfPresent(Bool.self, forKey: .isInstalled) ?? false
        self.binaryPath = try container.decodeIfPresent(String.self, forKey: .binaryPath)
        self.appPath = try container.decodeIfPresent(String.self, forKey: .appPath)
        self.assetDownloadUrl = try container.decodeIfPresent(String.self, forKey: .assetDownloadUrl)
        self.assetName = try container.decodeIfPresent(String.self, forKey: .assetName)
        self.lastChecked = try container.decodeIfPresent(Date.self, forKey: .lastChecked)
    }
    
    public var isOutdated: Bool {
        guard let latest = latestVersion, !latest.isEmpty, isInstalled else { return false }
        let cleanCurrent = currentVersion
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .components(separatedBy: CharacterSet.whitespacesAndNewlines).first ?? ""
        let cleanLatest = latest
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .components(separatedBy: CharacterSet.whitespacesAndNewlines).first ?? ""
        
        guard !cleanCurrent.isEmpty, !cleanLatest.isEmpty, cleanCurrent != "未安裝", cleanCurrent != "未檢測" else {
            return false
        }
        
        return cleanCurrent != cleanLatest && cleanCurrent.compare(cleanLatest, options: .numeric) == .orderedAscending
    }
}
