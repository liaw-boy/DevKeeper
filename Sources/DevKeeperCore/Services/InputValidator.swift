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
    
    /// GitHub owner or repository name; "." and ".." are rejected so they cannot alter an API path.
    public static func isValidRepoComponent(_ value: String) -> Bool {
        guard value != ".", value != ".." else { return false }
        return value.range(of: #"^[A-Za-z0-9_.-]{1,100}$"#, options: .regularExpression) != nil
    }
    
    /// Parses an https URL, optionally restricted to specific hosts (exact match or subdomain).
    /// Used for URLs that come from third-party API responses before they are opened.
    public static func httpsURL(_ string: String?, allowedHosts: [String]? = nil) -> URL? {
        guard let string, let url = URL(string: string),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if let allowedHosts {
            guard allowedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        }
        return url
    }
    
    /// Single-quotes a value for safe use as one shell word.
    public static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
