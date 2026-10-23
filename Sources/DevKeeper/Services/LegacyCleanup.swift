import Foundation
import Security

/// One-time removal of data left behind by features that no longer exist.
enum LegacyCleanup {
    private static let doneKey = "legacyGitHubToolsCleanupDone"
    
    /// The removed GitHub tracking feature stored a personal access token in the Keychain
    /// (and, in older versions, in UserDefaults). Nothing reads it anymore, so delete it.
    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.devkeeper.macos.github-token",
            kSecAttrAccount as String: "default"
        ]
        let status = SecItemDelete(query as CFDictionary)
        defaults.removeObject(forKey: "gitHubToken")
        if status == errSecSuccess || status == errSecItemNotFound {
            defaults.set(true, forKey: doneKey)
        }
    }
}
