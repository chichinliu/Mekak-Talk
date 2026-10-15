import Foundation
import Security
import TalkCore

enum KeyStore {
    private static let service = "com.chichinliu.mekak-talk"
    static func read(_ account: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func write(_ value: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw TalkError("無法清除鑰匙圈中的 API Key。") }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw TalkError("無法將 API Key 存入鑰匙圈。") }
        } else if status != errSecSuccess { throw TalkError("無法更新鑰匙圈中的 API Key。") }
    }
}

struct LocalStore {
    /// The development build carries a `.dev` bundle identifier and keeps its own settings and history.
    static let isDevelopment = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    private static let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    /// The release build's folder; speech models live here for both builds so they are downloaded once.
    static let releaseDirectory = base.appendingPathComponent("MekakTalk", isDirectory: true)

    let directory: URL
    init() {
        guard Self.isDevelopment else { directory = Self.releaseDirectory; return }
        directory = Self.base.appendingPathComponent("MekakTalk Dev", isDirectory: true)
        // Start from a copy of the release settings, so the dev build is usable straight away.
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path) {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? manager.copyItem(at: Self.releaseDirectory.appendingPathComponent("settings.json"),
                                  to: directory.appendingPathComponent("settings.json"))
        }
    }
    func load<T: Decodable>(_ type: T.Type, from name: String) throws -> T? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try JSONDecoder().decode(type, from: Data(contentsOf: url)) }
        catch {
            // Preserve unreadable data before a later settings save can replace it.
            let backup = directory.appendingPathComponent(name + ".unreadable-" + UUID().uuidString + ".bak")
            try FileManager.default.copyItem(at: url, to: backup)
            throw error
        }
    }
    func save<T: Encodable>(_ value: T, to name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(name)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
