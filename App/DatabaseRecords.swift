import Foundation
import GRDB

struct HistoryEntry: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    var id: Int64?
    var profileId: String
    var url: String
    var title: String
    var visitedAt: Double
    var visitCount: Int

    static let databaseTableName = "historyEntry"

    enum Columns {
        static let profileId = Column("profileId")
        static let url = Column("url")
        static let visitedAt = Column("visitedAt")
        static let visitCount = Column("visitCount")
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        return URL(string: url)?.host ?? url
    }
}

struct Bookmark: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    var id: Int64?
    var profileId: String
    var parentId: Int64?
    var title: String
    var url: String?
    var position: Double
    var isFolder: Bool
    var createdAt: Double

    static let databaseTableName = "bookmark"

    enum Columns {
        static let profileId = Column("profileId")
        static let parentId = Column("parentId")
        static let url = Column("url")
        static let position = Column("position")
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
