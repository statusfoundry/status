import Foundation
import SQLite3

public enum SQLiteValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case double(Double)
    case text(String)
}

public enum PersistenceError: Error, Equatable, LocalizedError, Sendable {
    case openFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)
    case missingColumn(String)
    case invalidDate(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            "Could not open database: \(message)"
        case .prepareFailed(let message):
            "Could not prepare SQL statement: \(message)"
        case .bindFailed(let message):
            "Could not bind SQL value: \(message)"
        case .stepFailed(let message):
            "Could not execute SQL statement: \(message)"
        case .missingColumn(let column):
            "Missing database column: \(column)"
        case .invalidDate(let value):
            "Invalid ISO-8601 date: \(value)"
        }
    }
}

public final class SQLiteDatabase {
    private var handle: OpaquePointer?

    public init(path: String) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let database {
                sqlite3_close(database)
            }
            throw PersistenceError.openFailed(message)
        }
        self.handle = database
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    public func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw PersistenceError.stepFailed(lastErrorMessage)
        }
    }

    public func executeBatch(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &error)
        if result != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(error)
            throw PersistenceError.stepFailed(message)
        }
    }

    public func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        var rows: [[String: SQLiteValue]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return rows
            }
            guard result == SQLITE_ROW else {
                throw PersistenceError.stepFailed(lastErrorMessage)
            }

            var row: [String: SQLiteValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                row[name] = value(in: statement, at: index)
            }
            rows.append(row)
        }
    }

    private func prepare(_ sql: String, statement: inout OpaquePointer?) throws {
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw PersistenceError.prepareFailed(lastErrorMessage)
        }
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .integer(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            }

            guard result == SQLITE_OK else {
                throw PersistenceError.bindFailed(lastErrorMessage)
            }
        }
    }

    private func value(in statement: OpaquePointer?, at index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .double(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            return .text(String(cString: sqlite3_column_text(statement, index)))
        case SQLITE_NULL:
            return .null
        default:
            return .null
        }
    }

    private var lastErrorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
