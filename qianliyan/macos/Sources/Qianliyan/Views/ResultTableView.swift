import SwiftUI
import AppKit

struct ResultTableView: View {
    @Bindable var viewModel: DBViewModel
    @State private var customColumnWidths: [Int: CGFloat] = [:]

    private func getColumnWidth(index: Int, result: QueryResultData, zoom: CGFloat, extraPerCol: CGFloat) -> CGFloat {
        if let custom = customColumnWidths[index] {
            return custom
        }
        return baseColumnWidth(for: index, in: result) * zoom + extraPerCol
    }

    var body: some View {
        let tab = viewModel.activeTab
        let zoom = CGFloat(viewModel.tableZoomLevel)

        VStack(spacing: 0) {
            if let error = tab.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                    Text("Error")
                        .font(.headline)
                    Text(error)
                        .font(.callout.monospaced())
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            } else if let result = tab.result {
                if result.columns.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                            .font(.title2)
                        Text("Statement executed successfully.")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let colCount = result.columns.count
                    let sortedIndices = tab.sortedRowIndices
                    let rowCount = sortedIndices.count
                    let indexColWidth = max(42, 48 * zoom)

                    GeometryReader { geo in
                        // Available width for data columns
                        let availableWidth = max(0, geo.size.width - indexColWidth - 16)
                        let totalBaseWidth = (0..<colCount).reduce(CGFloat(0)) {
                            $0 + baseColumnWidth(for: $1, in: result) * zoom
                        }
                        // Auto-fill extra space across all columns if window is wider than content
                        let extraPerCol: CGFloat = (colCount > 0 && availableWidth > totalBaseWidth)
                            ? (availableWidth - totalBaseWidth) / CGFloat(colCount)
                            : 0

                        ScrollView([.horizontal, .vertical]) {
                            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                                Section {
                                    ForEach(0..<rowCount, id: \.self) { r in
                                        let sortedIdx = sortedIndices[r]
                                        HStack(spacing: 0) {
                                            // Row Index
                                            Text("\((tab.page - 1) * tab.pageSize + r + 1)")
                                                .font(.system(size: 11 * zoom, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .frame(width: indexColWidth, alignment: .trailing)
                                                .padding(.trailing, 8)

                                            Divider().frame(height: 24 * zoom)

                                            // Row Cells (lightweight, double click to copy, no heavy per-cell contextMenu)
                                            ForEach(0..<colCount, id: \.self) { c in
                                                let cell = result[sortedIdx, c]
                                                let cellW = getColumnWidth(index: c, result: result, zoom: zoom, extraPerCol: extraPerCol)

                                                cellView(for: cell, zoom: zoom)
                                                    .frame(width: cellW, alignment: .leading)
                                                    .padding(.horizontal, 8 * zoom)
                                                    .contentShape(Rectangle())
                                                    .onTapGesture(count: 2) {
                                                        copyToClipboard(cell.description)
                                                        tab.statusMessage = "Copied '\(cell.description.prefix(30))' to clipboard"
                                                    }
                                                    .help("Double-click cell to copy value")

                                                Divider().frame(height: 24 * zoom)
                                            }
                                        }
                                        .padding(.vertical, 4 * zoom)
                                        .background(r % 2 == 1 ? Color.secondary.opacity(0.04) : Color.clear)
                                        .contextMenu {
                                            Button("Copy Row as JSON") {
                                                copyRowAsJSON(Array(result.row(at: sortedIdx)), columns: result.columns)
                                            }
                                            Button("Copy Row as CSV") {
                                                copyRowAsCSV(Array(result.row(at: sortedIdx)))
                                            }
                                        }

                                        Divider()
                                    }
                                } header: {
                                    // Pinned Header
                                    HStack(spacing: 0) {
                                        Text("#")
                                            .font(.system(size: 12 * zoom, weight: .bold))
                                            .foregroundColor(.secondary)
                                            .frame(width: indexColWidth, alignment: .trailing)
                                            .padding(.trailing, 8)

                                        Divider().frame(height: 28 * zoom)

                                        ForEach(0..<colCount, id: \.self) { c in
                                            let col = result.columns[c]
                                            let colW = getColumnWidth(index: c, result: result, zoom: zoom, extraPerCol: extraPerCol)

                                            HStack(spacing: 4) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(col.name)
                                                        .font(.system(size: 12 * zoom, weight: .bold))
                                                        .lineLimit(1)
                                                    Text(col.type.isEmpty ? "ANY" : col.type)
                                                        .font(.system(size: max(8, 9 * zoom), weight: .regular, design: .monospaced))
                                                        .foregroundColor(.secondary)
                                                }
                                                Spacer()
                                                if tab.sortColumnIndex == c {
                                                    Image(systemName: tab.sortAscending ? "chevron.up" : "chevron.down")
                                                        .font(.system(size: 10 * zoom, weight: .bold))
                                                        .foregroundColor(.accentColor)
                                                }
                                            }
                                            .frame(width: colW, alignment: .leading)
                                            .padding(.horizontal, 8 * zoom)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                tab.toggleSort(column: c)
                                            }
                                            .contextMenu {
                                                Button("Copy Column Name") {
                                                    copyToClipboard(col.name)
                                                }
                                                Button(tab.sortColumnIndex == c && tab.sortAscending ? "Sort Descending" : "Sort Ascending") {
                                                    tab.toggleSort(column: c)
                                                }
                                                if tab.sortColumnIndex == c {
                                                    Button("Clear Sort") {
                                                        tab.sortColumnIndex = nil
                                                    }
                                                }
                                                Divider()
                                                Button("Reset Column Width") {
                                                    customColumnWidths.removeValue(forKey: c)
                                                }
                                            }

                                            // Drag handle for column width resizing
                                            Rectangle()
                                                .fill(Color.secondary.opacity(0.2))
                                                .frame(width: 4, height: 28 * zoom)
                                                .contentShape(Rectangle())
                                                .gesture(
                                                    DragGesture()
                                                        .onChanged { value in
                                                            let currentW = getColumnWidth(index: c, result: result, zoom: zoom, extraPerCol: extraPerCol)
                                                            customColumnWidths[c] = max(50, currentW + value.translation.width)
                                                        }
                                                )
                                        }
                                    }
                                    .padding(.vertical, 4 * zoom)
                                    .background(Color(NSColor.windowBackgroundColor))
                                    .overlay(Divider(), alignment: .bottom)
                                }
                            }
                            .frame(minWidth: geo.size.width, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "tablecells.badge.ellipsis")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("No Query Results")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Select a table on the left or write a custom SQL query and click Run.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            }

            Divider()

            // Bottom Pagination & Status Bar
            HStack(spacing: 12) {
                // Status message
                if let status = tab.statusMessage {
                    Text(status)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Pagination Controls
                if let res = tab.result, !res.columns.isEmpty {
                    HStack(spacing: 6) {
                        Button(action: { viewModel.previousPage() }) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(tab.page <= 1)
                        .controlSize(.small)

                        Text("Page \(tab.page)")
                            .font(.caption.monospacedDigit())

                        Button(action: { viewModel.nextPage() }) {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!res.hasMore)
                        .controlSize(.small)

                        Menu {
                            Button("50 per page") { tab.pageSize = 50; viewModel.executeQuery() }
                            Button("100 per page") { tab.pageSize = 100; viewModel.executeQuery() }
                            Button("200 per page") { tab.pageSize = 200; viewModel.executeQuery() }
                            Button("500 per page") { tab.pageSize = 500; viewModel.executeQuery() }
                        } label: {
                            Text("\(tab.pageSize)/page")
                                .font(.caption2)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Divider().frame(height: 16)

                    // Zoom Controls ([-] 100% [+])
                    HStack(spacing: 3) {
                        Button(action: { viewModel.zoomOut() }) {
                            Image(systemName: "minus")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.tableZoomLevel <= 0.8)

                        Button(action: { viewModel.resetZoom() }) {
                            Text("\(Int((viewModel.tableZoomLevel * 100).rounded()))%")
                                .font(.caption2.monospacedDigit())
                        }
                        .buttonStyle(.plain)
                        .help("Click to reset zoom to 100%")

                        Button(action: { viewModel.zoomIn() }) {
                            Image(systemName: "plus")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.tableZoomLevel >= 1.6)
                    }
                    .padding(.horizontal, 4)

                    Divider().frame(height: 16)

                    // Export Menu
                    Menu {
                        Button(action: exportCSV) {
                            Label("Export to CSV...", systemImage: "tablecells")
                        }
                        Button(action: exportJSON) {
                            Label("Export to JSON...", systemImage: "curlybraces")
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Divider().frame(height: 16)

                    // Maximize / Restore Button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.isTableMaximized.toggle()
                        }
                    }) {
                        Image(systemName: viewModel.isTableMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.isTableMaximized ? "Restore Layout" : "Maximize Table")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func baseColumnWidth(for colIndex: Int, in result: QueryResultData) -> CGFloat {
        let nameLen = result.columns[colIndex].name.count
        return max(110, min(350, CGFloat(nameLen * 12 + 40)))
    }

    @ViewBuilder
    private func cellView(for value: CellValue, zoom: CGFloat) -> some View {
        let fontSize = max(10, 13 * zoom)
        switch value {
        case .null:
            Text("NULL")
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.4))
                .italic()
        case .integer(let v):
            Text("\(v)")
                .font(.system(size: fontSize, design: .monospaced))
        case .real(let v):
            Text(String(format: "%.4f", v))
                .font(.system(size: fontSize, design: .monospaced))
        case .text(let t):
            Text(t)
                .font(.system(size: fontSize))
                .lineLimit(1)
        case .blob(let size):
            HStack(spacing: 4) {
                Image(systemName: "doc.zipper")
                    .foregroundColor(.secondary)
                    .font(.caption2)
                Text("\(size) B")
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func copyToClipboard(_ str: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
    }

    private func copyRowAsJSON(_ row: [CellValue], columns: [ColumnInfo]) {
        var dict: [String: Any] = [:]
        for (i, col) in columns.enumerated() {
            if i < row.count {
                switch row[i] {
                case .null: dict[col.name] = NSNull()
                case .integer(let v): dict[col.name] = v
                case .real(let v): dict[col.name] = v
                case .text(let t): dict[col.name] = t
                case .blob(let size): dict[col.name] = "<Blob \(size)B>"
                }
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            copyToClipboard(str)
        }
    }

    private func copyRowAsCSV(_ row: [CellValue]) {
        let line = row.map { cell in
            switch cell {
            case .null: return ""
            case .integer(let v): return "\(v)"
            case .real(let v): return "\(v)"
            case .text(let t): return "\"\((t).replacingOccurrences(of: "\"", with: "\"\""))\""
            case .blob(let size): return "<Blob \(size)B>"
            }
        }.joined(separator: ",")
        copyToClipboard(line)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(viewModel.activeTab.title).csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? viewModel.exportCSV(for: viewModel.activeTab, to: url)
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(viewModel.activeTab.title).json"
        if panel.runModal() == .OK, let url = panel.url {
            try? viewModel.exportJSON(for: viewModel.activeTab, to: url)
        }
    }
}
