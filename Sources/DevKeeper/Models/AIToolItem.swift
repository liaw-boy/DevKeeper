import Foundation

public struct AIToolItem: Identifiable, Codable, Sendable, Hashable {
    public var id: String { command }
    public let name: String
    public let command: String
    public let vendor: String
    public let summary: String
    public let iconSymbol: String
    public var currentVersion: String
    public var latestVersion: String?
    public var isInstalled: Bool
    public var binaryPath: String?
    public var updateCommand: String
    public var installCommand: String
    public var websiteUrl: String
    public var lastChecked: Date?
    
    public init(
        name: String,
        command: String,
        vendor: String,
        summary: String,
        iconSymbol: String,
        currentVersion: String = "未檢測",
        latestVersion: String? = nil,
        isInstalled: Bool = false,
        binaryPath: String? = nil,
        updateCommand: String = "",
        installCommand: String = "",
        websiteUrl: String = "",
        lastChecked: Date? = nil
    ) {
        self.name = name
        self.command = command
        self.vendor = vendor
        self.summary = summary
        self.iconSymbol = iconSymbol
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.isInstalled = isInstalled
        self.binaryPath = binaryPath
        self.updateCommand = updateCommand
        self.installCommand = installCommand
        self.websiteUrl = websiteUrl
        self.lastChecked = lastChecked
    }
    
    public var isOutdated: Bool {
        guard isInstalled, let latest = latestVersion, !latest.isEmpty else { return false }
        // Clean current version: remove prefix 'v', 'V' and text after space
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
