import SwiftUI

struct QueryEditorView: View {
    @Bindable var viewModel: DBViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(viewModel.tabs) { tab in
                            let isActive = tab.id == viewModel.activeTabId
                            HStack(spacing: 6) {
                                Image(systemName: tab.tableName != nil ? "tablecells" : "terminal")
                                    .font(.caption2)
                                    .foregroundColor(isActive ? .accentColor : .secondary)

                                Text(tab.title)
                                    .font(.caption.weight(isActive ? .semibold : .regular))

                                if viewModel.tabs.count > 1 {
                                    Button(action: { viewModel.closeTab(id: tab.id) }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isActive ? Color(NSColor.textBackgroundColor) : Color.clear)
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.activeTabId = tab.id
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }

                Button(action: { viewModel.newTab() }) {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 4)

                Spacer()

                // History button
                Button(action: { viewModel.showHistory.toggle() }) {
                    Label("History", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.trailing, 8)
            }
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Active Tab SQL Editor
            TextEditor(text: Binding(
                get: { viewModel.activeTab.sql },
                set: {
                    viewModel.activeTab.sql = $0
                    if viewModel.activeTab.tableName != nil {
                        viewModel.activeTab.tableName = nil
                    }
                }
            ))
            .id(viewModel.activeTabId)
            .font(.system(.body, design: .monospaced))
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            // Control Bar
            HStack(spacing: 12) {
                Button(action: { viewModel.executeQuery() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Run")
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.activeTab.isExecuting)

                if viewModel.activeTab.isExecuting {
                    Button(action: { viewModel.cancelQuery() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                            Text("Cancel")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Text("⌘ + Return to execute")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}
