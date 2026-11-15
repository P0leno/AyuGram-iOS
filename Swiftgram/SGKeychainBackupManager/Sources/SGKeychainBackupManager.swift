import CryptoKit
import Foundation
import LocalAuthentication
import Security

public enum KeychainError: Error, LocalizedError {
    case duplicateEntry
    case unknown(OSStatus)
    case itemNotFound
    case invalidItemFormat
    case biometricFailed(String)
    case encryptionFailed(String)
    case invalidBackupFormat

    public var errorDescription: String? {
        switch self {
        case .duplicateEntry:
            return "Duplicate Keychain entry."
        case let .unknown(status):
            return "Keychain error (\(status))."
        case .itemNotFound:
            return "Backup session not found in Keychain."
        case .invalidItemFormat:
            return "Stored Keychain item has an unexpected format."
        case let .biometricFailed(message):
            return message
        case let .encryptionFailed(message):
            return message
        case .invalidBackupFormat:
            return "Invalid or corrupted backup file, or wrong passphrase."
        }
    }
}

public struct KeychainSessionEntry {
    public let id: String
    public let data: Data

    public init(id: String, data: Data) {
        self.id = id
        self.data = data
    }
}

private struct PortableEncryptedBackupEnvelope: Codable {
    let version: Int
    let salt: Data
    let rounds: Int
    let combinedBox: Data
}

private struct PortableBackupPayload: Codable {
    struct Entry: Codable {
        let id: String
        let data: Data
    }

    let exportedAt: Date
    let entries: [Entry]
}

public class KeychainBackupManager {
    public static let shared = KeychainBackupManager()

    private let service: String
    private let iCloudSyncKey = "ayugram.keychain.icloudSyncEnabled"
    private let requireBiometricsKey = "ayugram.keychain.requireBiometrics"

    private init() {
        let bundleId = Bundle.main.bundleIdentifier ?? "one.ayugram.ios"
        self.service = "\(bundleId).sessionsbackup"
    }

    // MARK: - Preferences

    /// Synchronize backed-up sessions through iCloud Keychain when entitlements allow.
    /// Automatically falls back to local Keychain on `-34018` in sideloaded builds.
    public var iCloudSyncEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: self.iCloudSyncKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: self.iCloudSyncKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: self.iCloudSyncKey)
        }
    }

    /// Require Face ID / Touch ID / device passcode before restoring a Keychain session on login.
    public var requireBiometricsForRestore: Bool {
        get {
            if UserDefaults.standard.object(forKey: self.requireBiometricsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: self.requireBiometricsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: self.requireBiometricsKey)
        }
    }

    // MARK: - Biometrics (Face ID / Touch ID / Passcode)

    public func canEvaluateBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    public func authenticateWithBiometrics(
        reason: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if !self.requireBiometricsForRestore {
            DispatchQueue.main.async {
                completion(.success(()))
            }
            return
        }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // If device has neither biometrics nor passcode configured, proceed without blocking login.
            DispatchQueue.main.async {
                completion(.success(()))
            }
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authError in
            DispatchQueue.main.async {
                if success {
                    completion(.success(()))
                } else {
                    let message = authError?.localizedDescription ?? "Authentication cancelled."
                    completion(.failure(KeychainError.biometricFailed(message)))
                }
            }
        }
    }

    // MARK: - Save Credentials

    public func saveSession(id: String, _ session: Data) throws {
        try self.saveSession(id: id, session, synchronizable: self.iCloudSyncEnabled)
    }

    private func saveSession(id: String, _ session: Data, synchronizable: Bool) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: id,
            kSecValueData as String: session,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecMissingEntitlement && synchronizable {
            // Sideloaded apps often lack iCloud Keychain entitlements; fall back to local Keychain.
            try self.saveSession(id: id, session, synchronizable: false)
            return
        }

        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: self.service,
                kSecAttrAccount as String: id,
                kSecAttrSynchronizable as String: synchronizable ? (kCFBooleanTrue as Any) : (kSecAttrSynchronizableAny as Any)
            ]

            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: session
            ]

            let updateStatus = SecItemUpdate(
                updateQuery as CFDictionary,
                attributesToUpdate as CFDictionary
            )

            if updateStatus == errSecMissingEntitlement && synchronizable {
                try self.saveSession(id: id, session, synchronizable: false)
                return
            }

            if updateStatus != errSecSuccess {
                throw KeychainError.unknown(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unknown(status)
        }
    }

    // MARK: - Retrieve Credentials

    public func retrieveSession(for id: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: id,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let sessionData = result as? Data else {
            throw KeychainError.itemNotFound
        }

        return sessionData
    }

    // MARK: - Delete Credentials

    public func deleteSession(for id: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: id,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unknown(status)
        }
    }

    // MARK: - Retrieve All Accounts

    public func getAllSessons() throws -> [Data] {
        return try self.getAllSessionEntries().map { $0.data }
    }

    public func getAllSessions() throws -> [Data] {
        return try self.getAllSessons()
    }

    public func getAllSessionEntries() throws -> [KeychainSessionEntry] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return []
        }

        guard status == errSecSuccess else {
            throw KeychainError.unknown(status)
        }

        let items: [[String: Any]]
        if let array = result as? [[String: Any]] {
            items = array
        } else if let single = result as? [String: Any] {
            items = [single]
        } else {
            throw KeychainError.invalidItemFormat
        }

        var seenIds = Set<String>()
        var entries: [KeychainSessionEntry] = []
        for item in items {
            guard let id = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data else {
                continue
            }
            if seenIds.insert(id).inserted {
                entries.append(KeychainSessionEntry(id: id, data: data))
            }
        }
        return entries
    }

    // MARK: - Delete All Sessions

    public func deleteAllSessions() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecItemNotFound {
            return
        }

        if status != errSecSuccess {
            throw KeychainError.unknown(status)
        }
    }

    // MARK: - Encrypted Portable Backup (.ayukey)

    private static let backupMagic = Data("AYUKEY1\n".utf8)
    private static let keyDerivationRounds = 100_000

    public func exportEncryptedBackup(passphrase: String) throws -> Data {
        guard !passphrase.isEmpty else {
            throw KeychainError.encryptionFailed("Passphrase cannot be empty.")
        }
        let entries = try self.getAllSessionEntries()
        guard !entries.isEmpty else {
            throw KeychainError.itemNotFound
        }

        let payload = PortableBackupPayload(
            exportedAt: Date(),
            entries: entries.map { PortableBackupPayload.Entry(id: $0.id, data: $0.data) }
        )
        let payloadData = try JSONEncoder().encode(payload)

        var saltBytes = [UInt8](repeating: 0, count: 16)
        let rngStatus = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        guard rngStatus == errSecSuccess else {
            throw KeychainError.encryptionFailed("Failed to generate random salt.")
        }
        let salt = Data(saltBytes)

        let key = Self.deriveKey(passphrase: passphrase, salt: salt, rounds: Self.keyDerivationRounds)
        let sealed = try AES.GCM.seal(payloadData, using: key)
        guard let combined = sealed.combined else {
            throw KeychainError.encryptionFailed("Failed to encode AES-GCM sealed box.")
        }

        let envelope = PortableEncryptedBackupEnvelope(
            version: 1,
            salt: salt,
            rounds: Self.keyDerivationRounds,
            combinedBox: combined
        )
        var result = Self.backupMagic
        result.append(try JSONEncoder().encode(envelope))
        return result
    }

    @discardableResult
    public func importEncryptedBackup(_ data: Data, passphrase: String) throws -> [KeychainSessionEntry] {
        guard !passphrase.isEmpty else {
            throw KeychainError.encryptionFailed("Passphrase cannot be empty.")
        }
        guard data.starts(with: Self.backupMagic) else {
            throw KeychainError.invalidBackupFormat
        }
        let body = data.dropFirst(Self.backupMagic.count)
        let envelope: PortableEncryptedBackupEnvelope
        do {
            envelope = try JSONDecoder().decode(PortableEncryptedBackupEnvelope.self, from: body)
        } catch {
            throw KeychainError.invalidBackupFormat
        }
        guard envelope.version == 1, envelope.rounds > 0 else {
            throw KeychainError.invalidBackupFormat
        }

        let key = Self.deriveKey(passphrase: passphrase, salt: envelope.salt, rounds: envelope.rounds)
        let decryptedData: Data
        do {
            let box = try AES.GCM.SealedBox(combined: envelope.combinedBox)
            decryptedData = try AES.GCM.open(box, using: key)
        } catch {
            throw KeychainError.invalidBackupFormat
        }

        let payload: PortableBackupPayload
        do {
            payload = try JSONDecoder().decode(PortableBackupPayload.self, from: decryptedData)
        } catch {
            throw KeychainError.invalidBackupFormat
        }

        var imported: [KeychainSessionEntry] = []
        for entry in payload.entries {
            try self.saveSession(id: entry.id, entry.data)
            imported.append(KeychainSessionEntry(id: entry.id, data: entry.data))
        }
        return imported
    }

    private static func deriveKey(passphrase: String, salt: Data, rounds: Int) -> SymmetricKey {
        // Iterated HMAC-SHA256 key derivation using CryptoKit (no CommonCrypto bridging required).
        let passwordKey = SymmetricKey(data: Data(passphrase.utf8))
        var u = Data(HMAC<SHA256>.authenticationCode(for: salt + Data([0, 0, 0, 1]), using: passwordKey))
        var dk = [UInt8](u)
        if rounds > 1 {
            for _ in 2...rounds {
                u = Data(HMAC<SHA256>.authenticationCode(for: u, using: passwordKey))
                for i in 0..<dk.count {
                    dk[i] ^= u[i]
                }
            }
        }
        return SymmetricKey(data: dk)
    }
}

