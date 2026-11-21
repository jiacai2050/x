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
    public let rowCount: Int
    public let columnCount: Int
    public let values: [CellValue]
    public let hasMore: Bool
    public let executionTimeMs: Double

    public init(columns: [ColumnInfo], rowCount: Int, columnCount: Int, values: [CellValue], hasMore: Bool, executionTimeMs: Double) {
        self.columns = columns
        self.rowCount = rowCount
        self.columnCount = columnCount
        self.values = values
        self.hasMore = hasMore
        self.executionTimeMs = executionTimeMs
    }

    public subscript(row: Int, col: Int) -> CellValue {
        values[row * columnCount + col]
    }

    public func row(at r: Int) -> ArraySlice<CellValue> {
        let start = r * columnCount
        return values[start..<(start + columnCount)]
    }

    public func appending(more: QueryResultData) -> QueryResultData {
        var newValues = self.values
        newValues.reserveCapacity(self.values.count + more.values.count)
        newValues.append(contentsOf: more.values)
        return QueryResultData(
            columns: self.columns,
            rowCount: self.rowCount + more.rowCount,
            columnCount: self.columnCount,
            values: newValues,
            hasMore: more.hasMore,
            executionTimeMs: self.executionTimeMs + more.executionTimeMs
        )
    }

    public func withHasMore(_ hasMore: Bool) -> QueryResultData {
        QueryResultData(
            columns: self.columns,
            rowCount: self.rowCount,
            columnCount: self.columnCount,
            values: self.values,
            hasMore: hasMore,
            executionTimeMs: self.executionTimeMs
        )
    }
}

public final class DBClient: @unchecked Sendable {
    private var handle: DbHandle?
    private let lock = NSLock()
    private var isClosing = false

    public init() {}

    deinit {
        close()
    }

    public var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return handle != nil
    }

    public func open(path: String?) throws {
        close()

        lock.lock()
        defer { lock.unlock() }
        isClosing = false

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
        lock.lock()
        guard let h = handle else {
            lock.unlock()
            return
        }
        isClosing = true
        // Interrupt any ongoing query safely before closing
        db_interrupt(h)
        handle = nil
        lock.unlock()

        db_close(h)
    }

    public func interrupt() {
        lock.lock()
        defer { lock.unlock() }
        if let h = handle {
            db_interrupt(h)
        }
    }

    private func getValidHandle() throws -> DbHandle {
        lock.lock()
        defer { lock.unlock() }
        guard let h = handle, !isClosing else {
            throw NSError(domain: "DBClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Database not open"])
        }
        return h
    }

    @inline(__always)
    private static func decodeSlice(_ slice: DbSlice) -> String {
        guard let ptr = slice.data, slice.size > 0 else { return "" }
        return String(decoding: UnsafeRawBufferPointer(start: ptr, count: slice.size), as: UTF8.self)
    }

    public func getSchema() async throws -> [TableInfo] {
        _ = try getValidHandle()

        return try await Task.detached { [weak self] in
            guard let self = self else {
                throw NSError(domain: "DBClient", code: 5, userInfo: [NSLocalizedDescriptionKey: "Client deallocated"])
            }
            let validH = try self.getValidHandle()

            guard let schemaPtr = db_get_schema(validH, nil) else {
                let msg = db_errmsg(validH).map { String(cString: $0) } ?? "Failed to inspect schema"
                throw NSError(domain: "DBClient", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            defer { db_free_schema(schemaPtr) }

            let schemaRes = schemaPtr.pointee
            let tblCount = Int(schemaRes.table_count)
            var tables: [TableInfo] = []
            tables.reserveCapacity(tblCount)

            for i in 0..<tblCount {
                let cTbl = schemaRes.tables[i]
                let tblName = DBClient.decodeSlice(cTbl.name)
                let tblSql: String? = cTbl.sql.data != nil && cTbl.sql.size > 0 ? DBClient.decodeSlice(cTbl.sql) : nil

                let colCount = Int(cTbl.column_count)
                var columns: [ColumnInfo] = []
                columns.reserveCapacity(colCount)
                for ci in 0..<colCount {
                    let cCol = cTbl.columns[ci]
                    let colName = DBClient.decodeSlice(cCol.name)
                    let colType = DBClient.decodeSlice(cCol.type_name)
                    columns.append(ColumnInfo(name: colName, type: colType, pk: Int(cCol.pk)))
                }

                let idxCount = Int(cTbl.index_count)
                var indexes: [IndexInfo] = []
                indexes.reserveCapacity(idxCount)
                for ii in 0..<idxCount {
                    let cIdx = cTbl.indexes[ii]
                    let idxName = DBClient.decodeSlice(cIdx.name)
                    let idxColCount = Int(cIdx.column_count)
                    var idxColumns: [String] = []
                    idxColumns.reserveCapacity(idxColCount)
                    for cii in 0..<idxColCount {
                        let cColName = DBClient.decodeSlice(cIdx.columns[cii])
                        idxColumns.append(cColName)
                    }
                    indexes.append(IndexInfo(name: idxName, unique: cIdx.is_unique, columns: idxColumns))
                }

                tables.append(TableInfo(
                    name: tblName,
                    sql: tblSql,
                    columns: columns,
                    indexes: indexes
                ))
            }

            return tables
        }.value
    }

    private static func parseResult(_ resPtr: UnsafeMutablePointer<DbBatchResult>) -> QueryResultData {
        let res = resPtr.pointee
        let colCount = Int(res.column_count)
        let rowCount = Int(res.row_count)

        var columns: [ColumnInfo] = []
        columns.reserveCapacity(colCount)
        for i in 0..<colCount {
            let col = res.columns[i]
            let name = DBClient.decodeSlice(col.name)
            let typeName = DBClient.decodeSlice(col.type_name)
            columns.append(ColumnInfo(name: name, type: typeName))
        }

        let totalValues = colCount * rowCount
        var values: [CellValue] = []
        values.reserveCapacity(totalValues)

        for idx in 0..<totalValues {
            let cVal = res.values[idx]
            switch cVal.type {
            case DB_TYPE_NULL:
                values.append(.null)
            case DB_TYPE_INTEGER:
                values.append(.integer(cVal.value.int_val))
            case DB_TYPE_REAL:
                values.append(.real(cVal.value.real_val))
            case DB_TYPE_TEXT:
                let slice = cVal.value.text_val
                if let ptr = slice.data, slice.size > 0 {
                    // Vectorized UTF-8 decoding with exact byte length, skipping strlen
                    let text = String(decoding: UnsafeRawBufferPointer(start: ptr, count: slice.size), as: UTF8.self)
                    values.append(.text(text))
                } else {
                    values.append(.text(""))
                }
            case DB_TYPE_BLOB:
                let size = cVal.value.blob_val.size
                values.append(.blob(size))
            default:
                values.append(.null)
            }
        }

        let execTimeMs = Double(res.execution_time_ns) / 1_000_000.0

        return QueryResultData(
            columns: columns,
            rowCount: rowCount,
            columnCount: colCount,
            values: values,
            hasMore: res.has_more,
            executionTimeMs: execTimeMs
        )
    }

    public func query(sql: String, limit: UInt32 = 500) async throws -> QueryResultData {
        _ = try getValidHandle()

        return try await Task.detached { [weak self] in
            guard let self = self else {
                throw NSError(domain: "DBClient", code: 5, userInfo: [NSLocalizedDescriptionKey: "Client deallocated"])
            }
            let validH = try self.getValidHandle()

            guard let resPtr = db_query(validH, sql, limit, nil) else {
                let msg = db_errmsg(validH).map { String(cString: $0) } ?? "Query failed"
                throw NSError(domain: "DBClient", code: 4, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            defer { db_free_result(resPtr) }

            return DBClient.parseResult(resPtr)
        }.value
    }

    public func fetchMore(limit: UInt32 = 100) async throws -> QueryResultData? {
        _ = try getValidHandle()

        return try await Task.detached { [weak self] in
            guard let self = self else {
                throw NSError(domain: "DBClient", code: 5, userInfo: [NSLocalizedDescriptionKey: "Client deallocated"])
            }
            let validH = try self.getValidHandle()

            var errPtr: UnsafeMutablePointer<CChar>? = nil
            guard let resPtr = db_fetch_more(validH, limit, &errPtr) else {
                if let errPtr = errPtr {
                    let msg = String(cString: errPtr)
                    db_free_string(errPtr)
                    throw NSError(domain: "DBClient", code: 6, userInfo: [NSLocalizedDescriptionKey: msg])
                }
                return nil
            }
            defer { db_free_result(resPtr) }

            return DBClient.parseResult(resPtr)
        }.value
    }

    public func closeCursor() {
        lock.lock()
        defer { lock.unlock() }
        if let h = handle {
            db_close_cursor(h)
        }
    }
}
