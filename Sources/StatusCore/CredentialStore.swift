import Foundation
import Security

public enum CredentialStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidReference(String)
    case randomGenerationFailed
    case storeFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidReference(let reference):
            "Invalid credential reference: \(reference)"
        case .randomGenerationFailed:
            "Could not generate a credential reference."
        case .storeFailed(let status):
            "Could not store credential in Keychain: \(status)"
        case .readFailed(let status):
            "Could not read credential from Keychain: \(status)"
        case .deleteFailed(let status):
            "Could not delete credential from Keychain: \(status)"
        }
    }
}

public protocol CredentialStore: Sendable {
    func store(_ data: Data, label: String) throws -> String
    func read(reference: String) throws -> Data?
    func delete(reference: String) throws
}

public enum CredentialReference {
    private static let alphabet = Array("0123456789abcdefghjkmnpqrstvwxyz")

    public static func make() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else {
            throw CredentialStoreError.randomGenerationFailed
        }

        var value = UInt64(Date().timeIntervalSince1970 * 1000)
        var characters: [Character] = []
        for _ in 0..<10 {
            characters.insert(alphabet[Int(value & 31)], at: characters.startIndex)
            value >>= 5
        }

        var bitBuffer = 0
        var bitCount = 0
        for byte in bytes {
            bitBuffer = (bitBuffer << 8) | Int(byte)
            bitCount += 8
            while bitCount >= 5, characters.count < 26 {
                let index = (bitBuffer >> (bitCount - 5)) & 31
                characters.append(alphabet[index])
                bitCount -= 5
            }
        }

        while characters.count < 26 {
            characters.append("0")
        }

        return "kc_" + String(characters.prefix(26))
    }

    public static func validate(_ reference: String) throws {
        let pattern = #"^kc_[0-9a-z]{26}$"#
        if reference.range(of: pattern, options: .regularExpression) == nil {
            throw CredentialStoreError.invalidReference(reference)
        }
    }
}

public final class KeychainCredentialStore: CredentialStore {
    private let service: String

    public init(service: String = "com.statusfoundry.status.credentials") {
        self.service = service
    }

    public func store(_ data: Data, label: String) throws -> String {
        let reference = try CredentialReference.make()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference,
            kSecAttrLabel as String: label,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialStoreError.storeFailed(status)
        }

        return reference
    }

    public func read(reference: String) throws -> Data? {
        try CredentialReference.validate(reference)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.readFailed(status)
        }
        return result as? Data
    }

    public func delete(reference: String) throws {
        try CredentialReference.validate(reference)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.deleteFailed(status)
        }
    }
}

public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func store(_ data: Data, label: String) throws -> String {
        let reference = try CredentialReference.make()
        lock.lock()
        storage[reference] = data
        lock.unlock()
        return reference
    }

    public func read(reference: String) throws -> Data? {
        try CredentialReference.validate(reference)
        lock.lock()
        let data = storage[reference]
        lock.unlock()
        return data
    }

    public func delete(reference: String) throws {
        try CredentialReference.validate(reference)
        lock.lock()
        storage.removeValue(forKey: reference)
        lock.unlock()
    }
}
