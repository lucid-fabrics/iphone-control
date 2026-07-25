import Foundation

/// Stores API keys in a local file in Application Support.
/// Avoids macOS Keychain password prompts for unsigned/dev-signed apps.
enum KeychainHelper {
    private static var storePath: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("iPhoneCompanion", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".keys")
    }()

    private static func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: storePath),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private static func saveAll(_ dict: [String: String]) {
        do {
            let data = try JSONEncoder().encode(dict)
            try data.write(to: storePath, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storePath.path)
        } catch {
            NSLog("[Companion] Failed to save keychain data: %@", error.localizedDescription)
        }
    }

    static func save(key: String, value: String) {
        var dict = loadAll()
        dict[key] = value
        saveAll(dict)
    }

    static func load(key: String) -> String? {
        loadAll()[key]
    }

    static func delete(key: String) {
        var dict = loadAll()
        dict.removeValue(forKey: key)
        saveAll(dict)
    }
}
