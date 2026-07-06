import Foundation
import GRDB

enum BookmarkStore {
    @discardableResult
    static func add(profileId: UUID, url: String, title: String, parentId: Int64? = nil) -> Bookmark? {
        let pid = profileId.uuidString
        let now = Date().timeIntervalSince1970
        return try? AppDatabase.shared.pool.write { db in
            let position = try nextPosition(db, profileId: pid, parentId: parentId)
            var bookmark = Bookmark(id: nil, profileId: pid, parentId: parentId,
                                    title: title, url: url, position: position,
                                    isFolder: false, createdAt: now)
            try bookmark.insert(db)
            return bookmark
        }
    }

    @discardableResult
    static func addFolder(profileId: UUID, title: String, parentId: Int64? = nil) -> Bookmark? {
        let pid = profileId.uuidString
        let now = Date().timeIntervalSince1970
        return try? AppDatabase.shared.pool.write { db in
            let position = try nextPosition(db, profileId: pid, parentId: parentId)
            var folder = Bookmark(id: nil, profileId: pid, parentId: parentId,
                                  title: title, url: nil, position: position,
                                  isFolder: true, createdAt: now)
            try folder.insert(db)
            return folder
        }
    }

    static func children(profileId: UUID, parentId: Int64?) -> [Bookmark] {
        (try? AppDatabase.shared.pool.read { db in
            var request = Bookmark.filter(Bookmark.Columns.profileId == profileId.uuidString)
            if let parentId {
                request = request.filter(Bookmark.Columns.parentId == parentId)
            } else {
                request = request.filter(Bookmark.Columns.parentId == nil)
            }
            return try request.order(Bookmark.Columns.position).fetchAll(db)
        }) ?? []
    }

    static func roots(profileId: UUID) -> [Bookmark] {
        children(profileId: profileId, parentId: nil)
    }

    static func search(profileId: UUID, query: String, limit: Int = 5) -> [Bookmark] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let like = "%\(trimmed)%"
        return (try? AppDatabase.shared.pool.read { db in
            try Bookmark.fetchAll(db, sql: """
                SELECT * FROM bookmark
                WHERE profileId = ? AND isFolder = 0 AND (title LIKE ? OR url LIKE ?)
                ORDER BY position LIMIT ?
                """, arguments: [profileId.uuidString, like, like, limit])
        }) ?? []
    }

    static func contains(profileId: UUID, url: String) -> Bool {
        let count = (try? AppDatabase.shared.pool.read { db in
            try Bookmark
                .filter(Bookmark.Columns.profileId == profileId.uuidString && Bookmark.Columns.url == url)
                .fetchCount(db)
        }) ?? 0
        return count > 0
    }

    static func delete(id: Int64) {
        try? AppDatabase.shared.pool.write { db in
            _ = try Bookmark.deleteOne(db, id: id)
        }
    }

    static func rename(id: Int64, title: String) {
        try? AppDatabase.shared.pool.write { db in
            try db.execute(sql: "UPDATE bookmark SET title = ? WHERE id = ?", arguments: [title, id])
        }
    }

    private static func nextPosition(_ db: Database, profileId: String, parentId: Int64?) throws -> Double {
        let sql: String
        let arguments: StatementArguments
        if let parentId {
            sql = "SELECT MAX(position) FROM bookmark WHERE profileId = ? AND parentId = ?"
            arguments = [profileId, parentId]
        } else {
            sql = "SELECT MAX(position) FROM bookmark WHERE profileId = ? AND parentId IS NULL"
            arguments = [profileId]
        }
        let maxPosition = try Double.fetchOne(db, sql: sql, arguments: arguments) ?? 0
        return maxPosition + 1024
    }
}
