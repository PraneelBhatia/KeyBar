import Foundation
import Security

public enum VaultError: LocalizedError {
    case keychain(OSStatus), corrupt, duplicate, missing, invalidInput
    public var errorDescription: String? {
        switch self {
        case .keychain(let code): "Keychain could not complete the request (\(code)). Unlock your login Keychain and try again."
        case .corrupt: "A KeyBar item could not be read. Check it in Keychain Access."
        case .duplicate: "That variable already exists. Choose another name or replace the existing key."
        case .missing: "This key is no longer in Keychain. Refresh KeyBar and try again."
        case .invalidInput: "Use a non-reserved uppercase variable name and a single key without whitespace."
        }
    }
}

/// Metadata and secret live in the same local, non-syncing Keychain item.
/// Listing returns attributes only; it never loads secret values.
public struct KeychainVault: Sendable {
    public static let defaultService = "app.keybar.vault.v1"
    private let service: String
    public var serviceName: String { service }
    public init(service: String = KeychainVault.defaultService) { self.service = service }
    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrSynchronizable as String: false]
    }
    private func query(_ variable: String) -> [String: Any] {
        var query = base
        query[kSecAttrAccount as String] = variable
        return query
    }
    public func list() throws -> [KeyRecord] {
        var query = base
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
        guard let rows = result as? [[String: Any]] else { throw VaultError.corrupt }
        return try rows.map { row in
            guard let data = row[kSecAttrGeneric as String] as? Data,
                  let record = try? JSONDecoder().decode(KeyRecord.self, from: data),
                  record.variable == row[kSecAttrAccount as String] as? String,
                  InputRules.validVariable(record.variable) else { throw VaultError.corrupt }
            return record
        }.sorted { $0.addedAt < $1.addedAt }
    }
    public func add(_ record: KeyRecord, secret: String) throws {
        guard InputRules.validVariable(record.variable), InputRules.validSecret(secret) else { throw VaultError.invalidInput }
        var item = query(record.variable)
        item[kSecAttrLabel as String] = "KeyBar · \(record.name)"
        item[kSecAttrGeneric as String] = try JSONEncoder().encode(record)
        item[kSecValueData as String] = Data(secret.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem { throw VaultError.duplicate }
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
    }
    public func secret(for variable: String) throws -> String {
        var query = query(variable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw VaultError.missing }
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw VaultError.corrupt }
        return value
    }
    public func update(_ record: KeyRecord, secret: String? = nil) throws {
        guard InputRules.validVariable(record.variable) else { throw VaultError.invalidInput }
        var changes: [String: Any] = [kSecAttrGeneric as String: try JSONEncoder().encode(record),
                                      kSecAttrLabel as String: "KeyBar · \(record.name)"]
        if let secret {
            guard InputRules.validSecret(secret) else { throw VaultError.invalidInput }
            changes[kSecValueData as String] = Data(secret.utf8)
        }
        let status = SecItemUpdate(query(record.variable) as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound { throw VaultError.missing }
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
    }
    public func delete(_ variable: String) throws {
        let status = SecItemDelete(query(variable) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError.keychain(status) }
    }
}
