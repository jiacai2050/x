import Foundation
import Observation
import SwiftUI
import AppKit

public struct RecentDB: Identifiable, Codable, Hashable {
    public var id: UUID
    public let name: String
    public let path: String
    public var lastOpened: Date

    enum CodingKeys: String, CodingKey {
        case id, name, path, lastOpened
    }

    public init(name: String, path: String, lastOpened: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.path = path
        self.lastOpened = lastOpened
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(String.self, forKey: .path)
        self.lastOpened = try container.decodeIfPresent(Date.self, forKey: .lastOpened) ?? Date()
    }
}

public enum ViewMode {
    case home
    case workspace
}

@Observable
public final class QueryTab: Identifiable {
    public let id = UUID()
    public var title: String
    public var sql: String
    public var result: QueryResultData? = nil
    public var isExecuting: Bool = false
    public var errorMessage: String? = nil
    public var statusMessage: String? = nil
    public var page: Int = 1
    public var pageSize: Int = 50
    public var tableName: String? = nil

    public init(title: String, sql: String, tableName: String? = nil) {
        self.title = title
        self.sql = sql
        self.tableName = tableName
    }
}

public struct HistoryItem: Identifiable, Hashable {
    public let id = UUID()
    public let sql: String
    public let timestamp: Date
    public let durationMs: Double
    public let rowCount: Int
}

@Observable
@MainActor
public final class DBViewModel {
    public var viewMode: ViewMode = .home
    public var currentRecent: RecentDB? = nil
    public var recentDatabases: [RecentDB] = []

    public var dbPath: String? = nil
    public var dbName: String = ""
    public var tables: [TableInfo] = []
    public var selectedTable: TableInfo? = nil
    public var selectedTableForDDL: TableInfo? = nil
    public var showHistory: Bool = false
    public var showNewDBSheet: Bool = false
    public var showAbout: Bool = false
    public var isTableMaximized: Bool = false
    public var tableZoomLevel: Double = 1.0

    // Multi-tabs
    public var tabs: [QueryTab]
    public var activeTabId: UUID

    // History
    public var history: [HistoryItem] = []

    public let client: DBClient = DBClient()

    private let recentKey = "qianliyan_recent_databases_v1"

    public init() {
        let defaultTab = QueryTab(title: "Query 1", sql: "")
        self.tabs = [defaultTab]
        self.activeTabId = defaultTab.id
        loadRecentDatabases()
    }

    public var activeTab: QueryTab {
        if let tab = tabs.first(where: { $0.id == activeTabId }) {
            return tab
        }
        return tabs[0]
    }

    public func backToHome() {
        client.close()
        self.dbPath = nil
        self.dbName = ""
        self.tables = []
        self.selectedTable = nil
        self.viewMode = .home
    }

    public func openRecent(_ recent: RecentDB) {
        openDatabase(path: recent.path, name: recent.name)
    }

    public func openFromPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true
        panel.showsTagField = false
        panel.allowedContentTypes = [] // Allow any sqlite / db file
        panel.prompt = "Open Database"

        if panel.runModal() == .OK, let url = panel.url {
            let existingEntry = recentDatabases.first(where: { $0.path == url.path })
            let defaultName = existingEntry?.name ?? url.deletingPathExtension().lastPathComponent
            openDatabase(path: url.path, name: defaultName)
        }
    }

    public func createNewDatabase() {
        showNewDBSheet = true
    }

    public func removeRecent(_ recent: RecentDB) {
        recentDatabases.removeAll(where: { $0.path == recent.path })
        saveRecentDatabases()
    }

    public struct ExportPayload: Codable {
        public let version: Int
        public let exportedAt: Date
        public let connections: [RecentDB]
    }

    public func exportConnections() {
        let panel = NSSavePanel()
        panel.showsTagField = false
        panel.allowedContentTypes = []
        panel.nameFieldStringValue = "qianliyan_connections.json"
        panel.prompt = "Export"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let payload = ExportPayload(
                    version: 1,
                    exportedAt: Date(),
                    connections: recentDatabases
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(payload)
                try data.write(to: url)
            } catch {
                activeTab.errorMessage = "Failed to export connections: \(error.localizedDescription)"
            }
        }
    }

    public func importConnections() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true
        panel.showsTagField = false
        panel.allowedContentTypes = []
        panel.prompt = "Import"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                var importedList: [RecentDB] = []

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let payload = try? decoder.decode(ExportPayload.self, from: data) {
                    importedList = payload.connections
                } else if let rawList = try? decoder.decode([RecentDB].self, from: data) {
                    importedList = rawList
                } else {
                    let standardDecoder = JSONDecoder()
                    if let rawList = try? standardDecoder.decode([RecentDB].self, from: data) {
                        importedList = rawList
                    } else {
                        return
                    }
                }

                // Merge into recentDatabases (update existing or prepend new)
                for item in importedList.reversed() {
                    recentDatabases.removeAll(where: { $0.path == item.path })
                    recentDatabases.insert(item, at: 0)
                }
                saveRecentDatabases()
            } catch {
                activeTab.errorMessage = "Failed to import connections: \(error.localizedDescription)"
            }
        }
    }

    public func openDatabase(path: String?, name: String? = nil) {
        do {
            try client.open(path: path)
            self.dbPath = path ?? "In-Memory Database"
            let existingEntry = path != nil ? recentDatabases.first(where: { $0.path == path }) : nil
            let resolvedName = name ?? existingEntry?.name ?? (path != nil ? URL(fileURLWithPath: path!).lastPathComponent : "In-Memory")
            self.dbName = resolvedName

            // Update recent list
            if let path = path {
                recordRecent(name: resolvedName, path: path)
            }

            self.viewMode = .workspace
            // Reset tabs
            self.tabs = [QueryTab(title: "Query 1", sql: "SELECT * FROM sqlite_master;")]
            self.activeTabId = tabs[0].id
            activeTab.statusMessage = "Connected to \(resolvedName)"
            refreshSchema()
        } catch {
            activeTab.errorMessage = error.localizedDescription
            activeTab.statusMessage = "Failed to open database"
        }
    }

    public func updateDatabaseName(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.dbName = trimmed
        if let path = self.dbPath {
            recordRecent(name: trimmed, path: path)
        }
        activeTab.statusMessage = "Database renamed to '\(trimmed)'"
    }

    public func renameRecentDatabase(path: String, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = recentDatabases.firstIndex(where: { $0.path == path }) {
            let item = recentDatabases[idx]
            let updated = RecentDB(name: trimmed, path: item.path, lastOpened: item.lastOpened)
            recentDatabases[idx] = updated
            saveRecentDatabases()
            if dbPath == path {
                self.dbName = trimmed
            }
        }
    }

    private func recordRecent(name: String, path: String) {
        recentDatabases.removeAll(where: { $0.path == path })
        let newEntry = RecentDB(name: name, path: path, lastOpened: Date())
        recentDatabases.insert(newEntry, at: 0)
        if recentDatabases.count > 20 { recentDatabases.removeLast() }
        saveRecentDatabases()
    }

    private func loadRecentDatabases() {
        if let data = UserDefaults.standard.data(forKey: recentKey),
           let list = try? JSONDecoder().decode([RecentDB].self, from: data) {
            // Filter out any legacy in-memory databases
            self.recentDatabases = list.filter { $0.path != ":memory:" }
        } else {
            self.recentDatabases = []
        }
    }

    private func saveRecentDatabases() {
        if let data = try? JSONEncoder().encode(recentDatabases) {
            UserDefaults.standard.set(data, forKey: recentKey)
        }
    }

    public func newTab(title: String? = nil, sql: String = "", tableName: String? = nil) {
        let tabNumber = tabs.count + 1
        let newTitle = title ?? "Query \(tabNumber)"
        let tab = QueryTab(title: newTitle, sql: sql, tableName: tableName)
        tabs.append(tab)
        activeTabId = tab.id
    }

    public func closeTab(id: UUID) {
        guard tabs.count > 1 else { return }
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            tabs.remove(at: index)
            if activeTabId == id {
                activeTabId = tabs[max(0, index - 1)].id
            }
        }
    }

    public func refreshSchema() {
        Task {
            do {
                self.tables = try await client.getSchema()
            } catch {
                activeTab.errorMessage = "Failed to load schema: \(error.localizedDescription)"
            }
        }
    }

    public func selectTable(_ table: TableInfo) {
        self.selectedTable = table
        if let existing = tabs.first(where: { $0.tableName == table.name }) {
            self.activeTabId = existing.id
            executeQuery()
        } else {
            newTab(title: table.name, sql: "SELECT * FROM \"\(table.name)\";", tableName: table.name)
            executeQuery()
        }
    }

    public func executeQuery() {
        let tab = activeTab
        let trimmed = tab.sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var execSql = trimmed
        if let tbl = tab.tableName {
            let offset = (tab.page - 1) * tab.pageSize
            execSql = "SELECT * FROM \"\(tbl)\" LIMIT \(tab.pageSize) OFFSET \(offset);"
        }

        tab.isExecuting = true
        tab.errorMessage = nil
        tab.statusMessage = "Executing query..."

        Task {
            do {
                let res = try await client.query(sql: execSql, limit: UInt32(tab.pageSize))
                tab.result = res
                tab.isExecuting = false

                let item = HistoryItem(
                    sql: trimmed,
                    timestamp: Date(),
                    durationMs: res.executionTimeMs,
                    rowCount: res.rows.count
                )
                self.history.insert(item, at: 0)
                if self.history.count > 100 { self.history.removeLast() }

                let countStr = "\(res.rows.count) row(s)"
                tab.statusMessage = "\(countStr) returned in \(String(format: "%.2f", res.executionTimeMs)) ms"
            } catch {
                tab.isExecuting = false
                tab.errorMessage = error.localizedDescription
                tab.statusMessage = "Query error"
            }
        }
    }

    public func nextPage() {
        guard let res = activeTab.result, res.hasMore else { return }
        activeTab.page += 1
        executeQuery()
    }

    public func previousPage() {
        guard activeTab.page > 1 else { return }
        activeTab.page -= 1
        executeQuery()
    }

    public func cancelQuery() {
        client.interrupt()
        activeTab.statusMessage = "Cancelling..."
    }

    public func exportCSV(for tab: QueryTab, to url: URL) throws {
        guard let res = tab.result else { return }
        var csv = ""
        csv += res.columns.map { "\"\($0.name.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",") + "\n"
        for row in res.rows {
            let line = row.map { cell -> String in
                switch cell {
                case .null: return ""
                case .integer(let v): return "\(v)"
                case .real(let v): return "\(v)"
                case .text(let t): return "\"\((t).replacingOccurrences(of: "\"", with: "\"\""))\""
                case .blob(let size): return "<Blob \(size)B>"
                }
            }.joined(separator: ",")
            csv += line + "\n"
        }
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    public func exportJSON(for tab: QueryTab, to url: URL) throws {
        guard let res = tab.result else { return }
        var list: [[String: Any]] = []
        for row in res.rows {
            var dict: [String: Any] = [:]
            for (i, col) in res.columns.enumerated() {
                if i < row.count {
                    let cell = row[i]
                    switch cell {
                    case .null: dict[col.name] = NSNull()
                    case .integer(let v): dict[col.name] = v
                    case .real(let v): dict[col.name] = v
                    case .text(let t): dict[col.name] = t
                    case .blob(let size): dict[col.name] = "<Blob \(size)B>"
                    }
                }
            }
            list.append(dict)
        }
        let data = try JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted])
        try data.write(to: url)
    }

    public func zoomIn() {
        if tableZoomLevel < 1.6 {
            tableZoomLevel = min(1.6, tableZoomLevel + 0.15)
        }
    }

    public func zoomOut() {
        if tableZoomLevel > 0.8 {
            tableZoomLevel = max(0.75, tableZoomLevel - 0.15)
        }
    }

    public func resetZoom() {
        tableZoomLevel = 1.0
    }
}
