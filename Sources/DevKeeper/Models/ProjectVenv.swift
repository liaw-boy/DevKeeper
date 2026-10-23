import Foundation

/// A project's Python virtual environment found under the user's projects folder.
public struct ProjectVenv: Identifiable, Hashable, Sendable {
    public var id: String { venvPath }
    public let projectName: String
    public let projectPath: String
    public let venvPath: String
    /// Python version the venv was created with (from pyvenv.cfg).
    public let pythonVersion: String
    public let requirementsFile: String?
    
    public var minorVersion: String {
        let parts = pythonVersion.split(separator: ".")
        return parts.count >= 2 ? "\(parts[0]).\(parts[1])" : pythonVersion
    }
    public var isEndOfLife: Bool { PythonLifecycle.isEndOfLife(minor: minorVersion) }
    public var venvName: String { URL(fileURLWithPath: venvPath).lastPathComponent }
}
