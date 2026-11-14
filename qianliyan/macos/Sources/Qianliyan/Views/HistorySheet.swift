import SwiftUI

struct HistorySheet: View {
    @Bindable var viewModel: DBViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Query History (\(viewModel.history.count))")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)

            Divider()

            if viewModel.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Query History Yet")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.history) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.timestamp, format: .dateTime.hour().minute().second())
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("\(item.rowCount) rows in \(String(format: "%.1f", item.durationMs)) ms")
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }

                        Text(item.sql)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(3)

                        HStack {
                            Spacer()
                            Button("Open in New Tab") {
                                viewModel.newTab(title: "History", sql: item.sql)
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Use in Active Tab") {
                                viewModel.activeTab.sql = item.sql
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
