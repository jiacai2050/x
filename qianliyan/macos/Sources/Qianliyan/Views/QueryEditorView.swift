import SwiftUI
import AppKit

struct MacSQLEditor: NSViewRepresentable {
    @Binding var text: String
    var onSelectionChanged: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacSQLEditor

        init(_ parent: MacSQLEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0, let range = Range(selectedRange, in: textView.string) {
                let selected = String(textView.string[range])
                let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
                // Filter out empty selection or a lonely semicolon so "Run Selection" is not triggered unintentionally
                if !trimmed.isEmpty && trimmed != ";" {
                    parent.onSelectionChanged?(selected)
                    return
                }
            }
            parent.onSelectionChanged?("")
        }

        // Handle Tab key to insert 4 spaces instead of shifting focus
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.insertText("    ", replacementRange: textView.selectedRange())
                return true
            }
            return false
        }
    }
}

struct QueryEditorView: View {
    @Bindable var viewModel: DBViewModel

    var body: some View {
        let tab = viewModel.activeTab
        let hasSelection = !(tab.selectedSQL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

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

            // Active Tab SQL Editor (Enhanced NSTextView wrapper)
            MacSQLEditor(
                text: Binding(
                    get: { viewModel.activeTab.sql },
                    set: {
                        viewModel.activeTab.sql = $0
                        if viewModel.activeTab.tableName != nil {
                            viewModel.activeTab.tableName = nil
                        }
                    }
                ),
                onSelectionChanged: { selected in
                    viewModel.activeTab.selectedSQL = selected.isEmpty ? nil : selected
                }
            )
            .id(viewModel.activeTabId)
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            // Control Bar
            HStack(spacing: 12) {
                Button(action: { viewModel.executeQuery() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text(hasSelection ? "Run Selection" : "Run")
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.activeTab.isExecuting)

                if hasSelection {
                    Button("Run Entire Script") {
                        viewModel.executeQuery(overrideSql: viewModel.activeTab.sql)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.activeTab.isExecuting)
                }

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
