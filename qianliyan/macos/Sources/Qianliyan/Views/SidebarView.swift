import SwiftUI
import AppKit

struct SidebarView: View {
    @Bindable var viewModel: DBViewModel
    @State private var isEditingName: Bool = false
    @State private var editingName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header Action Buttons
            HStack(spacing: 8) {
                Button(action: { viewModel.backToHome() }) {
                    Label("Databases", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Spacer()

                Button(action: { viewModel.refreshSchema() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh Schema")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Database info badge
            if let path = viewModel.dbPath {
                HStack(spacing: 8) {
                    Image(systemName: "cylinder.split.1x2")
                        .foregroundColor(.accentColor)
                        .font(.body)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(viewModel.dbName.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : viewModel.dbName)
                                .font(.caption.bold())
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Button(action: {
                                editingName = viewModel.dbName
                                isEditingName = true
                            }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Configure Database Name")
                            .popover(isPresented: $isEditingName, arrowEdge: .bottom) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Database Name")
                                        .font(.subheadline.bold())
                                    Text("Set a custom display name / alias for this database.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    TextField("e.g. Production Replica, Analytics DB", text: $editingName)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 240)
                                        .onSubmit {
                                            if !editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                viewModel.updateDatabaseName(editingName)
                                                isEditingName = false
                                            }
                                        }

                                    HStack {
                                        Spacer()
                                        Button("Cancel") {
                                            isEditingName = false
                                        }
                                        .controlSize(.small)

                                        Button("Save") {
                                            viewModel.updateDatabaseName(editingName)
                                            isEditingName = false
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .disabled(editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }
                                }
                                .padding(12)
                            }
                        }

                        let filename = URL(fileURLWithPath: path).lastPathComponent
                        if !viewModel.dbName.isEmpty && viewModel.dbName != filename && path != ":memory:" && path != "In-Memory Database" {
                            Text(filename)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                .contextMenu {
                    Button("Configure Name...") {
                        editingName = viewModel.dbName
                        isEditingName = true
                    }
                    if path != ":memory:" && path != "In-Memory Database" {
                        Divider()
                        Button("Reveal in Finder") {
                            let url = URL(fileURLWithPath: path)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        Button("Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(path, forType: .string)
                        }
                    }
                }
            }

            // Tables Tree
            List(selection: $viewModel.selectedTable) {
                Section("Tables (\(viewModel.tables.count))") {
                    ForEach(viewModel.tables) { table in
                        DisclosureGroup {
                            // 1. Columns
                            let pkCount = table.columns.filter(\.isPK).count
                            ForEach(table.columns) { col in
                                HStack(spacing: 6) {
                                    if col.isPK {
                                        Image(systemName: "key.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption2)
                                            .help("Primary Key")
                                    } else {
                                        Image(systemName: iconForType(col.type))
                                            .foregroundColor(.secondary)
                                            .font(.caption2)
                                    }

                                    Text(col.name)
                                        .font(.caption)
                                        .fontWeight(col.isPK ? .medium : .regular)

                                    Spacer()

                                    if col.isPK {
                                        let badgeText = pkCount > 1 ? "PK\(col.pk ?? 1)" : "PK"
                                        Text(badgeText)
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.15))
                                            .cornerRadius(3)
                                    }

                                    Text(col.type)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.leading, 8)
                            }

                            // 2. Indexes (if any)
                            if !table.indexes.isEmpty {
                                DisclosureGroup {
                                    ForEach(table.indexes) { idx in
                                        HStack(spacing: 6) {
                                            Image(systemName: "bolt.fill")
                                                .foregroundColor(idx.unique ? .blue : .secondary)
                                                .font(.caption2)

                                            Text(idx.name)
                                                .font(.system(size: 11, design: .monospaced))
                                                .lineLimit(1)
                                                .truncationMode(.middle)

                                            if !idx.columnNames.isEmpty {
                                                Text("(\(idx.columnNames.joined(separator: ", ")))")
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }

                                            Spacer()

                                            if idx.unique {
                                                Text("UNIQUE")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundColor(.blue)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.blue.opacity(0.15))
                                                    .cornerRadius(3)
                                            }
                                        }
                                        .padding(.leading, 12)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "bolt.horizontal.fill")
                                            .foregroundColor(.secondary)
                                            .font(.caption2)
                                        Text("Indexes (\(table.indexes.count))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.leading, 8)
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "tablecells")
                                    .foregroundColor(.blue)
                                Text(table.name)
                                    .fontWeight(.medium)
                                Spacer()
                                Button(action: { viewModel.selectedTableForDDL = table }) {
                                    Image(systemName: "info.circle")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("View Table DDL & Indexes")
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectTable(table)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func iconForType(_ type: String) -> String {
        let upper = type.uppercased()
        if upper.contains("INT") { return "number" }
        if upper.contains("REAL") || upper.contains("FLOAT") || upper.contains("DOUBLE") { return "percent" }
        if upper.contains("BLOB") { return "doc.zipper" }
        return "textformat"
    }
}
