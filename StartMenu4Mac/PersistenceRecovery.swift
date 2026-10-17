import Foundation

enum PersistenceSchemaVersionProbe: Equatable {
    case missing
    case value(Int)
    case invalid
}

enum PersistenceLoadIssue {
    case unreadablePreserved(URL)
    case unreadableUnpreserved

    var allowsOverwrite: Bool {
        switch self {
        case .unreadableUnpreserved:
            return false
        case .unreadablePreserved:
            return true
        }
    }
}

enum PersistenceCommit {
    static func save<Value>(
        _ candidate: Value,
        persist: (Value) -> Bool,
        publish: (Value) -> Void
    ) -> Bool {
        guard persist(candidate) else { return false }
        publish(candidate)
        return true
    }
}

enum PersistenceRecovery {
    private struct SchemaVersionEnvelope: Decodable {
        let version: Int?

        private enum CodingKeys: String, CodingKey {
            case version
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.version), try !container.decodeNil(forKey: .version) else {
                version = nil
                return
            }
            version = try container.decode(Int.self, forKey: .version)
        }
    }

    static func schemaVersion(in data: Data) -> PersistenceSchemaVersionProbe {
        guard let envelope = try? JSONDecoder().decode(SchemaVersionEnvelope.self, from: data) else {
            return .invalid
        }
        return envelope.version.map(PersistenceSchemaVersionProbe.value) ?? .missing
    }

    static func preserveUnreadableData(_ data: Data, originalURL: URL) -> URL? {
        let directory = originalURL.deletingLastPathComponent()
        let stem = originalURL.deletingPathExtension().lastPathComponent
        var suffix = 1

        while true {
            let filename = suffix == 1
                ? "\(stem).unreadable-backup.json"
                : "\(stem).unreadable-backup-\(suffix).json"
            let backupURL = directory.appendingPathComponent(filename)

            if FileManager.default.fileExists(atPath: backupURL.path) {
                if let existingData = try? Data(contentsOf: backupURL), existingData == data {
                    return backupURL
                }
                suffix += 1
                continue
            }

            do {
                try data.write(to: backupURL, options: [.atomic])
                return backupURL
            } catch {
                NSLog("Failed to preserve unreadable data at %@: %@", backupURL.path, error.localizedDescription)
                return nil
            }
        }
    }

    static func unreadableIssue(for data: Data, originalURL: URL) -> PersistenceLoadIssue {
        guard let backupURL = preserveUnreadableData(data, originalURL: originalURL) else {
            NSLog("Failed to preserve unreadable data for %@", originalURL.path)
            return .unreadableUnpreserved
        }
        return .unreadablePreserved(backupURL)
    }

#if DEBUG
    static func runSelfCheck() {
        func probe(_ string: String) -> PersistenceSchemaVersionProbe {
            schemaVersion(in: Data(string.utf8))
        }

        assert(probe("{\"version\":13}") == .value(13))
        assert(probe("{\"version\":14}") == .value(14))
        assert(probe("{}") == .missing)
        assert(probe("{\"version\":null}") == .missing)
        assert(probe("{\"version\":\"14\"}") == .invalid)
        assert(probe("[]") == .invalid)
        assert(probe("{\"version\":") == .invalid)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StartMenu4Mac-PersistenceRecovery-\(UUID().uuidString)", isDirectory: true)
        let originalURL = directory.appendingPathComponent("settings.json")
        let firstData = Data("first unreadable value".utf8)
        let secondData = Data("second unreadable value".utf8)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try firstData.write(to: originalURL, options: [.atomic])

            let firstBackup = preserveUnreadableData(firstData, originalURL: originalURL)
            assert(firstBackup?.lastPathComponent == "settings.unreadable-backup.json")
            assert(firstBackup.flatMap { try? Data(contentsOf: $0) } == firstData)
            assert((try? Data(contentsOf: originalURL)) == firstData)

            let reusedBackup = preserveUnreadableData(firstData, originalURL: originalURL)
            assert(reusedBackup == firstBackup)

            let secondBackup = preserveUnreadableData(secondData, originalURL: originalURL)
            assert(secondBackup?.lastPathComponent == "settings.unreadable-backup-2.json")
            assert(secondBackup.flatMap { try? Data(contentsOf: $0) } == secondData)
            assert((try? Data(contentsOf: originalURL)) == firstData)
        } catch {
            assertionFailure("PersistenceRecovery self-check setup failed: \(error)")
        }

        try? FileManager.default.removeItem(at: directory)
    }
#endif
}
