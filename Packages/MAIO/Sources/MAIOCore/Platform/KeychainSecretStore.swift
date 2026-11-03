import Foundation
import MAIOKit
import Security

/// 用系统钥匙串保存密钥（ADR-0009）。每个功能一个 service，互相隔离。
@MainActor
final class KeychainSecretStore: SecretService {
    enum KeychainError: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .status(code):
                let message = SecCopyErrorMessageString(code, nil) as String? ?? "未知错误"
                return "钥匙串操作失败（\(code)）：\(message)"
            }
        }
    }

    private let service: String
    /// 读一次后缓存，避免每次翻译都访问钥匙串
    private var cache: [String: String?] = [:]

    init(service: String) {
        self.service = service
    }

    func secret(for key: String) -> String? {
        if let cached = cache[key] {
            return cached
        }
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let value = status == errSecSuccess ? (result as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil
        cache[key] = value
        return value
    }

    func setSecret(_ value: String?, for key: String) throws {
        let deleteStatus = SecItemDelete(baseQuery(key) as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainError.status(deleteStatus)
        }
        cache[key] = .some(nil)
        guard let value, !value.isEmpty else { return }
        var item = baseQuery(key)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        cache[key] = value
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
