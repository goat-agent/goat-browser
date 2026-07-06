import Foundation

struct Profile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var colorIndex: Int
    let createdAt: Date

    init(id: UUID = UUID(), name: String, colorIndex: Int = 1, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.createdAt = createdAt
    }

    var cacheDirectoryName: String { "Profile-\(id.uuidString)" }

    var avatarInitial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}
