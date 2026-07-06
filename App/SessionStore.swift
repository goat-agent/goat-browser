import Foundation

struct TabSession: Codable, Sendable {
    var id: Int
    var url: String
    var title: String
    var groupId: String?
}

struct GroupSession: Codable, Sendable {
    var id: String
    var name: String
    var colorIndex: Int
    var isCollapsed: Bool
}

struct ProfileSession: Codable, Sendable {
    var profileId: String
    var activeTabId: Int?
    var tabs: [TabSession]
    var groups: [GroupSession]
}

struct SessionSnapshot: Codable, Sendable {
    var savedAt: Double
    var activeProfileId: String
    var profiles: [ProfileSession]
}

enum SessionStore {
    private static var fileURL: URL {
        AppDatabase.supportDirectory().appendingPathComponent("session.json")
    }

    static func save(_ snapshot: SessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let url = fileURL
        let tmp = url.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load() -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }
}
