import Foundation
import Security

/// Stores the GitHub personal access token in the macOS Keychain instead of UserDefaults.
public enum TokenStore {
    private static let service = "com.devkeeper.macos.github-token"
    private static let account = "default"
    private static let legacyDefaultsKey = "gitHubToken"
    
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
    
    /// Returns the stored token, migrating a legacy plaintext UserDefaults value on first use.
    public static func load() -> String {
        migrateLegacyIfNeeded()
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return "" }
        return token
    }
    
    /// Saves the token; an empty value deletes the Keychain item.
    @discardableResult
    public static func save(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        guard let data = trimmed.data(using: .utf8) else { return false }
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
    
    private static func migrateLegacyIfNeeded() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: legacyDefaultsKey) else { return }
        if legacy.isEmpty || save(legacy) {
            defaults.removeObject(forKey: legacyDefaultsKey)
        }
    }
}
