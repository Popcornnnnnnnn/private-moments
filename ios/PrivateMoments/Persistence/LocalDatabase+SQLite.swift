import Foundation
import SQLite3

extension LocalDatabase {
    func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")

        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?

        guard sqlite3_exec(handle, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite execution failed"
            sqlite3_free(errorMessage)
            throw LocalDatabaseError.sqlite(message)
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LocalDatabaseError.sqlite(errorMessage)
        }

        return statement
    }

    func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LocalDatabaseError.sqlite(errorMessage)
        }
    }

    func count(
        _ sql: String,
        bind: ((OpaquePointer) throws -> Void)? = nil
    ) throws -> Int {
        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bind?(statement)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LocalDatabaseError.sqlite(errorMessage)
        }

        return Int(sqlite3_column_int64(statement, 0))
    }

    func bind(_ value: String?, to index: Int32, in statement: OpaquePointer) throws {
        let status: Int32

        if let value {
            status = sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
        } else {
            status = sqlite3_bind_null(statement, index)
        }

        guard status == SQLITE_OK else {
            throw LocalDatabaseError.sqlite(errorMessage)
        }
    }

    func bind(_ value: Int?, to index: Int32, in statement: OpaquePointer) throws {
        let status: Int32

        if let value {
            status = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        } else {
            status = sqlite3_bind_null(statement, index)
        }

        guard status == SQLITE_OK else {
            throw LocalDatabaseError.sqlite(errorMessage)
        }
    }

    func bind(_ value: Date?, to index: Int32, in statement: OpaquePointer) throws {
        try bind(value.map(Self.encodeDate), to: index, in: statement)
    }

    func text(_ statement: OpaquePointer, _ index: Int32) throws -> String {
        guard let text = optionalText(statement, index) else {
            throw LocalDatabaseError.missingColumn(Int(index))
        }

        return text
    }

    func optionalText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }

        return String(cString: value)
    }

    func optionalInt(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }

        return Int(sqlite3_column_int64(statement, index))
    }

    func date(_ statement: OpaquePointer, _ index: Int32) throws -> Date {
        let value = try text(statement, index)

        guard let date = Self.decodeDate(value) else {
            throw LocalDatabaseError.invalidDate(value)
        }

        return date
    }

    func optionalDate(_ statement: OpaquePointer, _ index: Int32) throws -> Date? {
        guard let value = optionalText(statement, index) else {
            return nil
        }

        guard let date = Self.decodeDate(value) else {
            throw LocalDatabaseError.invalidDate(value)
        }

        return date
    }

    static func encodeDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func decodeDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    var errorMessage: String {
        String(cString: sqlite3_errmsg(handle))
    }
}
