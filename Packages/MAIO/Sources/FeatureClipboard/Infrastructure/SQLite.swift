import Foundation
import SQLite3

/// 很薄的 SQLite 封装（ADR-0010）。不是线程安全的：只在 ClipStore 这个 actor 里使用。
final class SQLiteDatabase {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? {
            "数据库错误：\(message)"
        }
    }

    /// 绑定参数
    enum Value {
        case int(Int64)
        case text(String)
        case blob(Data)
        case null
    }

    private var handle: OpaquePointer?

    init(path: String) throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开 \(path)"
            sqlite3_close(handle)
            throw Failure(message: message)
        }
        sqlite3_busy_timeout(handle, 2000)
    }

    deinit {
        sqlite3_close(handle)
    }

    var lastInsertID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    var changes: Int {
        Int(sqlite3_changes(handle))
    }

    /// 执行不带参数的多条语句（建表等）
    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "未知错误"
            sqlite3_free(error)
            throw Failure(message: message)
        }
    }

    /// 执行一条语句并逐行读取结果
    func query(_ sql: String, _ values: [Value] = [], row: (Row) throws -> Void = { _ in }) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            try bind(value, at: Int32(offset + 1), in: statement)
        }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return
            }
            guard result == SQLITE_ROW else { throw lastError() }
            try row(Row(statement: statement))
        }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func bind(_ value: Value, at index: Int32, in statement: OpaquePointer?) throws {
        // SQLITE_TRANSIENT：让 SQLite 立即复制数据
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result: Int32 = switch value {
        case let .int(number): sqlite3_bind_int64(statement, index, number)
        case let .text(text): sqlite3_bind_text(statement, index, text, -1, transient)
        case let .blob(data): data.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), transient)
            }
        case .null: sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw lastError() }
    }

    private func lastError() -> Failure {
        Failure(message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "未知错误")
    }

    /// 当前结果行。只在 query 的回调里有效。
    struct Row {
        let statement: OpaquePointer?

        func int(_ column: Int32) -> Int64 {
            sqlite3_column_int64(statement, column)
        }

        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }

        func blob(_ column: Int32) -> Data? {
            guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
        }
    }
}
