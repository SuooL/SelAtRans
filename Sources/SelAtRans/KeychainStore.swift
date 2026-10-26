import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case operationFailed(OSStatus)
    var errorDescription: String? { "无法访问 macOS 钥匙串，请确认已解锁并允许 SelAtRans 访问。" }
}

struct KeychainStore {
    private let service = "io.github.suool.SelAtRans.api"
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func read(account: String) throws -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw KeychainError.operationFailed(status) }
        return key
    }

    func save(_ key: String, account: String) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary,
                                  [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError.operationFailed(added) }
        } else if status != errSecSuccess { throw KeychainError.operationFailed(status) }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.operationFailed(status) }
    }

    func deleteProfile(id: UUID) throws {
        var request: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                      kSecAttrService as String: service,
                                      kSecReturnAttributes as String: true,
                                      kSecMatchLimit as String: kSecMatchLimitAll]
        request[kSecReturnData as String] = false
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return }
        guard status == errSecSuccess else { throw KeychainError.operationFailed(status) }
        for item in result as? [[String: Any]] ?? [] {
            if let account = item[kSecAttrAccount as String] as? String, account.hasPrefix(id.uuidString + "|") {
                try delete(account: account)
            }
        }
    }
}
