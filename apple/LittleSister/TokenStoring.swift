//
//  TokenStoring.swift
//  LittleSister
//

import Foundation
import Security

protocol TokenStoring {
    func loadToken() -> String?
    func save(token: String)
    func deleteToken()
}

final class KeychainTokenStore: TokenStoring {
    private let service: String
    private let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "LittleSister",
        account: String = "bearer-token"
    ) {
        self.service = service
        self.account = account
    }

    func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(token: String) {
        let data = Data(token.utf8)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // kSecAttrAccessibleAfterFirstUnlock lets the polling loop read the
            // token while the screen is locked, without requiring user presence.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let searchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            _ = SecItemUpdate(
                searchQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
        }
    }

    func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}
