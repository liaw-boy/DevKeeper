import Foundation

/// Allowlist validation for values that end up inside shell command strings.
public enum InputValidator {
    private static let namePattern = #"^[A-Za-z0-9@][A-Za-z0-9@/._+-]{0,213}$"#
    private static let versionPattern = #"^[A-Za-z0-9][A-Za-z0-9._+!-]{0,63}$"#
    
    public static func isValidPackageName(_ value: String) -> Bool {
        value.range(of: namePattern, options: .regularExpression) != nil
    }
    
    public static func isValidVersion(_ value: String) -> Bool {
        value.range(of: versionPattern, options: .regularExpression) != nil
    }
    
    /// Returns the name unchanged when it is safe to embed in a shell command, otherwise nil.
    public static func safeName(_ value: String) -> String? {
        isValidPackageName(value) ? value : nil
    }
}
