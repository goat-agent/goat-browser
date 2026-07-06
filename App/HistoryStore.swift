import Foundation
import GRDB

enum HistoryStore {
    static func record(profileId: UUID, url: String, title: String) {
        guard let scheme = URL(string: url)?.scheme, scheme == "http" || scheme == "https" else { return }
        let pid = profileId.uuidString
        let now = Date().timeIntervalSince1970
        try? AppDatabase.shared.pool.write { db in
            if var entry = try HistoryEntry
                .filter(HistoryEntry.Columns.profileId == pid && HistoryEntry.Columns.url == url)
                .fetchOne(db) {
                entry.visitCount += 1
                entry.visitedAt = now
                if !title.isEmpty { entry.title = title }
                try entry.update(db)
            } else {
                var entry = HistoryEntry(id: nil, profileId: pid, url: url,
                                         title: title, visitedAt: now, visitCount: 1)
                try entry.insert(db)
            }
        }
    }

    static func updateTitle(profileId: UUID, url: String, title: String) {
        guard !title.isEmpty else { return }
        let pid = profileId.uuidString
        try? AppDatabase.shared.pool.write { db in
            try db.execute(sql: "UPDATE historyEntry SET title = ? WHERE profileId = ? AND url = ?",
                           arguments: [title, pid, url])
        }
    }

    static func search(profileId: UUID, query: String, limit: Int = 6) -> [HistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let pattern = trimmed
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { "\"\($0)\"*" }
            .joined(separator: " ")
        guard !pattern.isEmpty else { return [] }
        return (try? AppDatabase.shared.pool.read { db in
            try HistoryEntry.fetchAll(db, sql: """
                SELECT historyEntry.* FROM historyEntry
                JOIN historyEntryFTS ON historyEntryFTS.rowid = historyEntry.id
                WHERE historyEntry.profileId = ? AND historyEntryFTS MATCH ?
                ORDER BY historyEntry.visitCount DESC, historyEntry.visitedAt DESC
                LIMIT ?
                """, arguments: [profileId.uuidString, pattern, limit])
        }) ?? []
    }

    static func recent(profileId: UUID, limit: Int = 50) -> [HistoryEntry] {
        (try? AppDatabase.shared.pool.read { db in
            try HistoryEntry
                .filter(HistoryEntry.Columns.profileId == profileId.uuidString)
                .order(HistoryEntry.Columns.visitedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    static func topSites(profileId: UUID, limit: Int = 8) -> [HistoryEntry] {
        (try? AppDatabase.shared.pool.read { db in
            try HistoryEntry
                .filter(HistoryEntry.Columns.profileId == profileId.uuidString)
                .order(HistoryEntry.Columns.visitCount.desc, HistoryEntry.Columns.visitedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    static func clear(profileId: UUID) {
        try? AppDatabase.shared.pool.write { db in
            try HistoryEntry
                .filter(HistoryEntry.Columns.profileId == profileId.uuidString)
                .deleteAll(db)
        }
    }

    static func clearAll() {
        try? AppDatabase.shared.pool.write { db in
            try HistoryEntry.deleteAll(db)
        }
    }
}
