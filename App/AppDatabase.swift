import Foundation
import GRDB

final class AppDatabase: Sendable {
    static let shared = try! AppDatabase()

    let pool: DatabasePool

    init() throws {
        let directory = AppDatabase.supportDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pool = try DatabasePool(path: directory.appendingPathComponent("GoatBrowser.sqlite").path)
        try Self.migrator.migrate(pool)
    }

    static func supportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Goat Browser", isDirectory: true)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "historyEntry") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("profileId", .text).notNull().indexed()
                t.column("url", .text).notNull()
                t.column("title", .text).notNull().defaults(to: "")
                t.column("visitedAt", .double).notNull()
                t.column("visitCount", .integer).notNull().defaults(to: 1)
                t.uniqueKey(["profileId", "url"])
            }
            try db.create(virtualTable: "historyEntryFTS", using: FTS5()) { t in
                t.synchronize(withTable: "historyEntry")
                t.column("url")
                t.column("title")
                t.tokenizer = .unicode61()
            }
            try db.create(table: "bookmark") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("profileId", .text).notNull().indexed()
                t.column("parentId", .integer)
                t.column("title", .text).notNull()
                t.column("url", .text)
                t.column("position", .double).notNull().defaults(to: 0)
                t.column("isFolder", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .double).notNull()
            }
        }
        return migrator
    }
}
