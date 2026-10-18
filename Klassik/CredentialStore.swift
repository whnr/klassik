import Foundation
import Security

/// Keeps the server URL and username in UserDefaults and the password in the Keychain.
struct CredentialStore {
    var defaults: UserDefaults = .standard

    private static let urlKey = "server.url"
    private static let usernameKey = "server.username"
    private static let service = "de.whnr.klassik.server"

    func load() -> ServerCredentials? {
        guard let url = defaults.url(forKey: Self.urlKey),
            let username = defaults.string(forKey: Self.usernameKey),
            let password = Self.readPassword(account: username)
        else { return nil }
        return ServerCredentials(url: url, username: username, password: password)
    }

    func save(_ credentials: ServerCredentials) throws {
        try Self.writePassword(credentials.password, account: credentials.username)
        defaults.set(credentials.url, forKey: Self.urlKey)
        defaults.set(credentials.username, forKey: Self.usernameKey)
    }

    func clear() {
        if let username = defaults.string(forKey: Self.usernameKey) {
            SecItemDelete(Self.query(account: username) as CFDictionary)
        }
        defaults.removeObject(forKey: Self.urlKey)
        defaults.removeObject(forKey: Self.usernameKey)
    }

    struct KeychainError: LocalizedError {
        var status: OSStatus
        var errorDescription: String? { "Could not save the password in the Keychain (status \(status))." }
    }

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readPassword(account: String) -> String? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func writePassword(_ password: String, account: String) throws {
        SecItemDelete(query(account: account) as CFDictionary)
        var item = query(account: account)
        item[kSecValueData as String] = Data(password.utf8)
        // Playback continues while the phone is locked, so later requests must reach the password.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}
