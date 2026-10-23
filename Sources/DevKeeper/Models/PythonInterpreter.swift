import Foundation

public enum PythonSource: String, Sendable, Codable {
    case system = "Apple 內建"
    case homebrew = "Homebrew"
    case pyenv = "pyenv"
    case uv = "uv"
}

public struct PythonInterpreter: Identifiable, Hashable, Sendable {
    public var id: String { path }
    /// Executable path used to run this interpreter (stable symlink where available).
    public let path: String
    public let version: String
    public let source: PythonSource
    /// True when the interpreter carries a PEP 668 EXTERNALLY-MANAGED marker, so pip writes are refused.
    public let isExternallyManaged: Bool
    public let hasPip: Bool
    
    public var minorVersion: String {
        let parts = version.split(separator: ".")
        return parts.count >= 2 ? "\(parts[0]).\(parts[1])" : version
    }
    
    /// System Python belongs to macOS and cannot be upgraded from here.
    public var canUpgrade: Bool { source != .system }
}

/// An installable or upgradable Python release offered by a version manager.
public struct PythonRelease: Identifiable, Hashable, Sendable {
    public var id: String { "\(source.rawValue)-\(version)" }
    public let source: PythonSource
    /// Full version for uv/pyenv, minor version (e.g. "3.13") for Homebrew formulae.
    public let version: String
}
