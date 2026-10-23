import Foundation

/// The Python interpreter DevKeeper uses for pip scans and fixes.
/// Kept as a small synchronous holder because command strings are built in non-async model code.
public enum PythonRuntime {
    public static let selectedPathKey = "pythonInterpreterPath"
    
    private static let lock = NSLock()
    private static var _current: PythonInterpreter?
    
    public static var current: PythonInterpreter? {
        lock.lock(); defer { lock.unlock() }
        return _current
    }
    
    public static func setCurrent(_ interpreter: PythonInterpreter?) {
        lock.lock(); _current = interpreter; lock.unlock()
    }
    
    /// Shell word that runs the selected interpreter; falls back to `python3` on PATH.
    public static var executable: String {
        guard let path = current?.path else { return "python3" }
        return InputValidator.shellQuoted(path)
    }
    
    /// Why package changes are refused for the selected interpreter, or nil when writes are allowed.
    public static var writeBlockReason: String? {
        guard let current, current.isExternallyManaged else { return nil }
        return "目前使用的 Python \(current.version)（\(current.source.rawValue)）受 PEP 668 保護，不允許用 pip 直接修改。請在偏好設定改用未受管理的 Python，或把工具搬到獨立環境。"
    }
}
