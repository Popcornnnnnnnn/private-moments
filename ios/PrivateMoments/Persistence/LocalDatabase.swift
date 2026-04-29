import Foundation
import SQLite3

final class LocalDatabase {
    let handle: OpaquePointer
    static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func open() throws -> LocalDatabase {
        var database: OpaquePointer?
        let url = try AppDirectories.databaseURL()
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open local database"
            if let database {
                sqlite3_close(database)
            }
            throw LocalDatabaseError.sqlite(message)
        }

        let localDatabase = LocalDatabase(handle: database)
        try localDatabase.configure()
        try localDatabase.migrate()
        try localDatabase.normalizeStoredMediaPaths()
        return localDatabase
    }

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }
}
