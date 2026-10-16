import Foundation
import Security

/// What survives an app restart: the refresh token and whose it is.
/// The access token is never stored; it lives in memory only.
struct StoredSession: Codable, Equatable {
    let refreshToken: String
    let userId: String
}

protocol SessionStorage: AnyObject {
    func load() -> StoredSession?
    func save(_ session: StoredSession)
    func clear()
}

/// Keeps the session in the Keychain, readable after the first unlock and
/// never copied to another device or a backup.
final class KeychainSessionStorage: SessionStorage {
    private let service = "co.rivium.auth"
    private let account: String
    private let accessGroup: String?

    /// One entry per project, so two apps keys never share a session.
    init(apiKey: String, accessGroup: String?) {
        self.account = "session." + String(RiviumNonce.sha256(apiKey).prefix(16))
        self.accessGroup = accessGroup
    }

    private func query() -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let group = accessGroup { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    func load() -> StoredSession? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    func save(_ session: StoredSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query() as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query()
            add.merge(attributes) { _, new in new }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(query() as CFDictionary)
    }
}

/// For tests, and for apps that do not want the session to outlive the process.
final class MemorySessionStorage: SessionStorage {
    private let lock = NSLock()
    private var value: StoredSession?

    init(_ value: StoredSession? = nil) { self.value = value }

    func load() -> StoredSession? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func save(_ session: StoredSession) {
        lock.lock(); defer { lock.unlock() }
        value = session
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        value = nil
    }
}
