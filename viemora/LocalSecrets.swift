import Foundation

enum APIKeyStore {
    static var apiKey: String? {
        if let env = ProcessInfo.processInfo.environment["LPAGENT_API_KEY"]?.trimmedNonEmpty {
            return env
        }
        return readEnvAPIKey()
    }

    static func saveAPIKey(_ value: String) throws {
        guard let key = value.trimmedNonEmpty else {
            try? FileManager.default.removeItem(at: LocalConfig.envFileURL)
            return
        }

        try writeEnvAPIKey(key)
    }

    private static func readEnvAPIKey() -> String? {
        guard let content = try? String(contentsOf: LocalConfig.envFileURL, encoding: .utf8) else {
            return nil
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard name == "LPAGENT_API_KEY" || name == "API_KEY" else { continue }

            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2,
               ((value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                (value.hasPrefix("'") && value.hasSuffix("'"))) {
                value.removeFirst()
                value.removeLast()
            }
            return value.trimmedNonEmpty
        }
        return nil
    }

    private static func writeEnvAPIKey(_ key: String) throws {
        try LocalConfig.ensureAppSupportDirectory()
        try "LPAGENT_API_KEY=\(key)\n".write(to: LocalConfig.envFileURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: LocalConfig.envFileURL.path)
    }
}

enum LocalConfig {
    static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("viemora", isDirectory: true)
    }

    static var envFileURL: URL {
        appSupportDirectory.appendingPathComponent(".env")
    }

    static func ensureAppSupportDirectory() throws {
        try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
