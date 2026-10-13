import Foundation
import SQLite3

/// A single column value moving in/out of SQLite.
enum SQLiteValue {
    case text(String)
    case int(Int64)
    case double(Double)
    case null

    var stringValue: String? {
        if case .text(let s) = self { return s }
        return nil
    }
    var intValue: Int64? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int64(d)
        default: return nil
        }
    }
    var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }
}

enum SQLiteError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)

    var description: String {
        switch self {
        case .open(let m): return "SQLite open failed: \(m)"
        case .prepare(let m): return "SQLite prepare failed: \(m)"
        case .step(let m): return "SQLite step failed: \(m)"
        }
    }
}

// SQLite wants this sentinel so it copies bound strings instead of referencing them.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin wrapper over the system libsqlite3 C API. No external dependencies.
final class SQLiteDB {
    private var handle: OpaquePointer?

    init(path: String) throws {
        if sqlite3_open(path, &handle) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw SQLiteError.open(msg)
        }
        sqlite3_busy_timeout(handle, 3000)
    }

    deinit {
        sqlite3_close(handle)
    }

    /// Run one or more statements with no parameters (DDL, pragmas).
    func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw SQLiteError.step(msg)
        }
    }

    private func prepare(_ sql: String, _ params: [SQLiteValue]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw SQLiteError.prepare(msg)
        }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .int(let n): sqlite3_bind_int64(stmt, idx, n)
            case .double(let d): sqlite3_bind_double(stmt, idx, d)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
        return stmt
    }

    /// Execute a parameterized write; returns last inserted row id.
    @discardableResult
    func run(_ sql: String, _ params: [SQLiteValue] = []) throws -> Int64 {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw SQLiteError.step(msg)
        }
        return sqlite3_last_insert_rowid(handle)
    }

    /// Execute a parameterized query; returns rows as positional value arrays.
    func query(_ sql: String, _ params: [SQLiteValue] = []) throws -> [[SQLiteValue]] {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var rows: [[SQLiteValue]] = []
        let cols = sqlite3_column_count(stmt)
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [SQLiteValue] = []
            row.reserveCapacity(Int(cols))
            for c in 0..<cols {
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER:
                    row.append(.int(sqlite3_column_int64(stmt, c)))
                case SQLITE_FLOAT:
                    row.append(.double(sqlite3_column_double(stmt, c)))
                case SQLITE_NULL:
                    row.append(.null)
                default:
                    if let cstr = sqlite3_column_text(stmt, c) {
                        row.append(.text(String(cString: cstr)))
                    } else {
                        row.append(.null)
                    }
                }
            }
            rows.append(row)
        }
        return rows
    }
}
