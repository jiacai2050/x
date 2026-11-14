import SwiftUI
import AppKit

struct DDLSheet: View {
    let table: TableInfo
    @Environment(\.dismiss) private var dismiss
    @State private var copied: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(table.name)
                        .font(.headline)
                    Text("\(table.columns.count) columns, \(table.indexes.count) index(es)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: copyDDL) {
                    Label(copied ? "Copied!" : "Copy DDL", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // DDL Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Schema DDL")
                            .font(.subheadline.bold())

                        Text(table.sql ?? "CREATE TABLE \"\(table.name)\" (/* DDL unavailable */);")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                    }

                    // Indexes Section
                    if !table.indexes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Indexes (\(table.indexes.count))")
                                .font(.subheadline.bold())

                            VStack(spacing: 0) {
                                ForEach(table.indexes) { idx in
                                    HStack {
                                        Image(systemName: "bolt.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption2)

                                        Text(idx.name)
                                            .font(.system(.caption, design: .monospaced))

                                        if !idx.columnNames.isEmpty {
                                            Text("(\(idx.columnNames.joined(separator: ", ")))")
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        if idx.unique {
                                            Text("UNIQUE")
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.15))
                                                .foregroundColor(.blue)
                                                .cornerRadius(4)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    Divider()
                                }
                            }
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 550, minHeight: 400)
    }

    private func copyDDL() {
        if let ddl = table.sql {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ddl, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copied = false
            }
        }
    }
}
