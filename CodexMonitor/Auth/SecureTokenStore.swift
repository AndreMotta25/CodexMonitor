import Foundation
import Security

struct Credentials: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let accountID: String?
}

/// App and widget share this Keychain access group; no credentials enter the snapshot.
/// All mutations and migration must be performed under the session's interprocess lock.
struct SecureTokenStore {
    private var sharedQuery: [String: Any] {
        query(group: SharedSnapshotStore.groupID)
    }

    private func query(group: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.andremotta.codexmonitor.session",
         kSecAttrAccount as String: "dedicated-device-session",
         kSecAttrAccessGroup as String: group]
    }

    func read() throws -> Credentials? { try read(query: sharedQuery) }

    private func read(query: [String: Any]) throws -> Credentials? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(Credentials.self, from: data)
    }

    func save(_ credentials: Credentials) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(credentials),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(sharedQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let result = SecItemAdd(sharedQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard result == errSecSuccess else { throw KeychainError(status: result) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }

    func migrateLegacySessionIfNeeded() throws {
        #if !WIDGET_EXTENSION
        // Keep the old app-private item intact until the shared save has succeeded.
        if try read() == nil, let legacy = try read(query: legacyQuery) { try save(legacy) }
        try delete(query: legacyQuery)
        #endif
    }

    func clear() throws {
        try delete(query: sharedQuery)
        #if !WIDGET_EXTENSION
        try delete(query: legacyQuery)
        #endif
    }

    #if !WIDGET_EXTENSION
    private var legacyQuery: [String: Any] {
        query(group: Bundle.main.object(forInfoDictionaryKey: "LegacyKeychainAccessGroup") as? String
              ?? "HA9DK5S5U3.com.andremotta.codexmonitor")
    }
    #endif

    private func delete(query: [String: Any]) throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Não foi possível acessar a sessão segura (\(status)). Desbloqueie o iPhone e tente novamente." }
    }
}
