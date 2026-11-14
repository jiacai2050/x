import Foundation
import CQianliyan

public struct ColumnInfo: Identifiable, Hashable, Codable, Sendable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let pk: Int?

    public var isPK: Bool {
        (pk ?? 0) > 0
    }

    public init(name: String, type: String, pk: Int? = nil) {
        self.name = name
        self.type = type
        self.pk = pk
    }
}

public struct IndexInfo: Identifiable, Hashable, Codable, Sendable {
    public var id: String { name }
    public let name: String
    public let unique: Bool
    public let columns: [String]?

    public var columnNames: [String] {
        columns ?? []
    }

    public init(name: String, unique: Bool, columns: [String]? = nil) {
        self.name = name
        self.unique = unique
        self.columns = columns
    }
}

public struct TableInfo: Identifiable, Hashable, Codable, Sendable {
    public var id: String { name }
    public let name: String
    public let sql: String?
    public let columns: [ColumnInfo]
    public let indexes: [IndexInfo]
}

public enum CellValue: Hashable, Sendable, CustomStringConvertible {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Int) // Byte count

    public var description: String {
        switch self {
        case .null: return "NULL"
        case .integer(let v): return String(v)
        case .real(let v): return String(format: "%.4f", v)
        case .text(let v): return v
        case .blob(let size): return "<\(size) bytes>"
        }
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

public struct QueryResultData: Sendable {
    public let columns: [ColumnInfo]
    public let rows: [[CellValue]]
    public let hasMore: Bool
    public let executionTimeMs: Double
}

public final class DBClient: @unchecked Sendable {
    private var handle: DbHandle?

    public init() {}

    deinit {
        close()
    }

    public var isOpen: Bool {
        handle != nullPtr
    }

    private var nullPtr: DbHandle? {
        nil
    }

    public func open(path: String?) throws {
        close()

        var errPtr: UnsafeMutablePointer<CChar>? = nil
        let cPath = path.flatMap { strdup($0) }
        defer {
            if let cPath = cPath { free(cPath) }
        }

        guard let h = db_open(cPath, &errPtr) else {
            let msg = errPtr.map { String(cString: $0) } ?? "Unknown open error"
            db_free_string(errPtr)
            throw NSError(domain: "DBClient", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        self.handle = h
    }

    public func close() {
        if let h = handle {
            db_close(h)
            handle = nil
        }
    }

    public func interrupt() {
        if let h = handle {
            db_interrupt(h)
        }
    }

    public func getSchema() async throws -> [TableInfo] {
        guard let h = handle else {
            throw NSError(domain: "DBClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Database not open"])
        }

        return try await Task.detached {
            var errPtr: UnsafeMutablePointer<CChar>? = nil
            guard let jsonPtr = db_get_schema_json(h, &errPtr) else {
                let msg = errPtr.map { String(cString: $0) } ?? "Failed to inspect schema"
                db_free_string(errPtr)
                throw NSError(domain: "DBClient", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            defer { db_free_string(jsonPtr) }

            let jsonString = String(cString: jsonPtr)
            guard let data = jsonString.data(using: .utf8) else { return [] }
            let decoder = JSONDecoder()
            return try decoder.decode([TableInfo].self, from: data)
        }.value
    }

    public func query(sql: String, limit: UInt32 = 500) async throws -> QueryResultData {
        guard let h = handle else {
            throw NSError(domain: "DBClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Database not open"])
        }

        return try await Task.detached {
            var errPtr: UnsafeMutablePointer<CChar>? = nil
            guard let resPtr = db_query(h, sql, limit, &errPtr) else {
                let msg = errPtr.map { String(cString: $0) } ?? "Query failed"
                db_free_string(errPtr)
                throw NSError(domain: "DBClient", code: 4, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            defer { db_free_result(resPtr) }

            let res = resPtr.pointee
            let colCount = Int(res.column_count)
            let rowCount = Int(res.row_count)

            var columns: [ColumnInfo] = []
            columns.reserveCapacity(colCount)
            for i in 0..<colCount {
                let col = res.columns[i]
                let name = col.name != nil ? String(cString: col.name!) : ""
                let typeName = col.type_name != nil ? String(cString: col.type_name!) : ""
                columns.append(ColumnInfo(name: name, type: typeName))
            }

            var rows: [[CellValue]] = []
            rows.reserveCapacity(rowCount)

            for r in 0..<rowCount {
                var rowCells: [CellValue] = []
                rowCells.reserveCapacity(colCount)
                for c in 0..<colCount {
                    let idx = r * colCount + c
                    let cVal = res.values[idx]
                    switch cVal.type {
                    case DB_TYPE_NULL:
                        rowCells.append(.null)
                    case DB_TYPE_INTEGER:
                        rowCells.append(.integer(cVal.value.int_val))
                    case DB_TYPE_REAL:
                        rowCells.append(.real(cVal.value.real_val))
                    case DB_TYPE_TEXT:
                        let text = cVal.value.text_val != nil ? String(cString: cVal.value.text_val!) : ""
                        rowCells.append(.text(text))
                    case DB_TYPE_BLOB:
                        let size = cVal.value.blob_val.size
                        rowCells.append(.blob(size))
                    default:
                        rowCells.append(.null)
                    }
                }
                rows.append(rowCells)
            }

            let execTimeMs = Double(res.execution_time_ns) / 1_000_000.0

            return QueryResultData(
                columns: columns,
                rows: rows,
                hasMore: res.has_more,
                executionTimeMs: execTimeMs
            )
        }.value
    }
}
