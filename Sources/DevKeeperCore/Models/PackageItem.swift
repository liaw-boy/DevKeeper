import Foundation

public enum PackageType: String, Codable, CaseIterable, Sendable {
    case npm = "npm"
    case python = "Python"
    case brewFormula = "Formula"
    case brewCask = "Cask"
    case database = "資料庫"
    case uvTool = "uv"
    
    public var displayName: String {
        switch self {
        case .npm: return "npm 全域套件"
        case .python: return "Python 套件 (pip)"
        case .brewFormula: return "Homebrew Formula"
        case .brewCask: return "Homebrew Cask"
        case .database: return "資料庫服務"
        case .uvTool: return "uv 工具"
        }
    }
    
    public var sfSymbol: String {
        switch self {
        case .npm: return "cube"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .brewFormula: return "terminal"
        case .brewCask: return "macwindow"
        case .database: return "cylinder.split.1x2"
        case .uvTool: return "wrench.and.screwdriver"
        }
    }
}

public enum UpdateStatus: String, Codable, Sendable {
    case upToDate = "Up to Date"
    case patch = "Patch Update"
    case minor = "Minor Update"
    case major = "Major Update"
    case updateAvailable = "Update Available"
    case checking = "Checking"
    case error = "Check Failed"
    
    public var isOutdated: Bool {
        switch self {
        case .patch, .minor, .major, .updateAvailable:
            return true
        default:
            return false
        }
    }
    
    public var localizedTitle: String {
        switch self {
        case .upToDate: return "最新版本"
        case .patch: return "修復更新"
        case .minor: return "次要更新"
        case .major: return "重大改版"
        case .updateAvailable: return "有新版本"
        case .checking: return "檢查中"
        case .error: return "無法取得"
        }
    }
    
    public var sfSymbol: String {
        switch self {
        case .upToDate: return "checkmark.circle"
        case .patch: return "arrow.up.circle"
        case .minor: return "arrow.up.circle.fill"
        case .major: return "exclamationmark.arrow.triangle.2.circlepath"
        case .updateAvailable: return "arrow.triangle.2.circlepath"
        case .checking: return "arrow.clockwise"
        case .error: return "questionmark.circle"
        }
    }
}

public struct PackageItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public var currentVersion: String
    public var latestVersion: String?
    public let type: PackageType
    public var status: UpdateStatus
    public var description: String?
    public var homepage: String?
    public var isUpdating: Bool = false
    public var isUninstalling: Bool = false
    /// Homebrew formulae installed only because another package needs them.
    public var isDependencyOnly: Bool = false
    /// Set on a uv tool that was installed with an exact version (`==x`) while a newer version exists:
    /// `uv tool upgrade` will not move it, so no update is offered.
    public var pinnedSpecifier: String?
    
    public init(
        name: String,
        currentVersion: String,
        latestVersion: String? = nil,
        type: PackageType,
        status: UpdateStatus = .checking,
        description: String? = nil,
        homepage: String? = nil
    ) {
        self.id = "\(type.rawValue):\(name)"
        self.name = name
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.type = type
        self.status = status
        self.description = description
        self.homepage = homepage
    }
    
    public var upgradeCommand: String {
        guard InputValidator.isValidPackageName(name) else { return "" }
        switch type {
        case .brewFormula:
            return "brew upgrade \(name)"
        case .brewCask:
            return "brew upgrade --cask \(name)"
        case .npm:
            return "npm install -g \(name)"
        case .python:
            return "\(PythonRuntime.executable) -m pip install --upgrade \(name)"
        case .database:
            return "brew upgrade \(name) && brew services restart \(name)"
        case .uvTool:
            return "uv tool upgrade \(name)"
        }
    }
    
    /// Exact commands run when this package is removed; listed in the confirmation panel.
    public var uninstallCommands: [String] {
        guard InputValidator.isValidPackageName(name) else { return [] }
        switch type {
        case .npm:
            return ["npm uninstall -g \(name)"]
        case .python:
            return ["\(PythonRuntime.executable) -m pip uninstall -y \(name)"]
        case .brewFormula:
            return ["brew uninstall \(name)", "brew autoremove"]
        case .brewCask:
            return ["brew uninstall --zap --cask \(name)"]
        case .database:
            return ["brew services stop \(name)", "brew uninstall \(name)", "brew autoremove"]
        case .uvTool:
            return ["uv tool uninstall \(name)"]
        }
    }
    
    public static func computeUpdateStatus(current: String, latest: String?) -> UpdateStatus {
        guard let latest = latest, !latest.isEmpty else {
            return .checking
        }
        
        let cleanCurrent = current.trimmingCharacters(in: CharacterSet(charactersIn: "v^~"))
        let cleanLatest = latest.trimmingCharacters(in: CharacterSet(charactersIn: "v^~"))
        
        if cleanCurrent == cleanLatest {
            return .upToDate
        }
        
        let currentParts = cleanCurrent.split(separator: ".").compactMap { Int($0.split(separator: "-").first?.split(separator: "_").first ?? "") }
        let latestParts = cleanLatest.split(separator: ".").compactMap { Int($0.split(separator: "-").first?.split(separator: "_").first ?? "") }
        
        guard currentParts.count >= 2, latestParts.count >= 2 else {
            return .updateAvailable
        }
        
        if latestParts[0] > currentParts[0] {
            return .major
        } else if latestParts[0] == currentParts[0] {
            if latestParts[1] > currentParts[1] {
                return .minor
            } else if latestParts[1] == currentParts[1] {
                if latestParts.count >= 3 && currentParts.count >= 3 && latestParts[2] > currentParts[2] {
                    return .patch
                }
            }
        }
        
        return .upToDate
    }
}

public struct DatabaseServiceItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public var status: ServiceStatus
    public var user: String?
    public var file: String?
    public var isActionRunning: Bool = false
    
    public init(name: String, status: ServiceStatus, user: String? = nil, file: String? = nil) {
        self.id = name
        self.name = name
        self.status = status
        self.user = user
        self.file = file
    }
}

public enum ServiceStatus: String, Codable, Sendable {
    case started = "started"
    case stopped = "stopped"
    case error = "error"
    case unknown = "unknown"
    
    public var localizedTitle: String {
        switch self {
        case .started: return "運行中"
        case .stopped: return "已停止"
        case .error: return "異常"
        case .unknown: return "未註冊"
        }
    }
    
    public var sfSymbol: String {
        switch self {
        case .started: return "play.circle.fill"
        case .stopped: return "stop.circle"
        case .error: return "exclamationmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}
