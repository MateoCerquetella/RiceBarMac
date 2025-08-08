import Foundation

struct ApplyAction: Codable, Equatable, Hashable {
    enum Kind: String, Codable { case created, updated }
    var kind: Kind
    var source: String
    var destination: String
    var backup: String?
}

struct ApplyRecord: Codable {
    var timestamp: Date
    var actions: [ApplyAction]
}

enum ApplyRecordStore {
    static func recordURL(for profileDir: URL) -> URL {
        profileDir.appendingPathComponent(".ricebar-last-apply.json")
    }

    static func save(_ record: ApplyRecord, to profileDir: URL) {
        let url = recordURL(for: profileDir)
        do {
            let data = try JSONEncoder().encode(record)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed saving apply record: \(error)")
        }
    }

    static func load(from profileDir: URL) -> ApplyRecord? {
        let url = recordURL(for: profileDir)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ApplyRecord.self, from: data)
    }
}
