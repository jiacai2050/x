import SwiftUI
import AppKit

struct HomeView: View {
    @Bindable var viewModel: DBViewModel
    @State private var renamingItem: RecentDB? = nil
    @State private var newRecentName: String = ""
    @State private var selectedRecentId: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "eye.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Qianliyan")
                            .font(.title2.bold())
                        Text("Modern Native Database Client")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Actions
                HStack(spacing: 10) {
                    Button(action: { viewModel.openFromPicker() }) {
                        Label("Open DB...", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    Button(action: { viewModel.createNewDatabase() }) {
                        Label("New DB...", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button(action: { viewModel.showAbout = true }) {
                        Label("About", systemImage: "info.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(.bar)

            Divider()

            // Body: Recent Databases
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("Recent Databases")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("(\(viewModel.recentDatabases.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: { viewModel.importConnections() }) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Import connections from JSON")

                    Button(action: { viewModel.exportConnections() }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Export connections to JSON")
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)

                if viewModel.recentDatabases.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "cylinder.split.1x2")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No Recent Databases")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Open an existing SQLite database or create a new one above.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedRecentId) {
                        ForEach(viewModel.recentDatabases) { item in
                            HStack(spacing: 14) {
                                // DB Icon
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.blue.opacity(0.12))
                                        .frame(width: 38, height: 38)

                                    Image(systemName: "cylinder.split.1x2")
                                        .font(.system(size: 18))
                                        .foregroundColor(.blue)
                                }

                                // DB Details
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name)
                                        .font(.body.weight(.semibold))

                                    Text(item.path)
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer()

                                // Last Opened
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(item.lastOpened, style: .date)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(item.lastOpened, style: .time)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundColor(.secondary.opacity(0.7))
                                }

                                Button(action: { viewModel.openRecent(item) }) {
                                    Text("Open")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .tag(item.id)
                            .onTapGesture(count: 2) {
                                viewModel.openRecent(item)
                            }
                            .contextMenu {
                                Button("Open") {
                                    viewModel.openRecent(item)
                                }
                                Button("Configure Name...") {
                                    newRecentName = item.name
                                    renamingItem = item
                                }
                                if item.path != ":memory:" {
                                    Button("Reveal in Finder") {
                                        let url = URL(fileURLWithPath: item.path)
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }
                                }
                                Divider()
                                Button("Remove from Recent", role: .destructive) {
                                    viewModel.removeRecent(item)
                                }
                            }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    .padding(.horizontal, 20)
                    .onKeyPress(.return) {
                        if let id = selectedRecentId,
                           let item = viewModel.recentDatabases.first(where: { $0.id == id }) {
                            viewModel.openRecent(item)
                            return .handled
                        }
                        return .ignored
                    }
                }
            }

            Divider()

            // Footer Bar
            HStack(spacing: 12) {
                Text("Qianliyan v1.0.0")
                    .foregroundColor(.secondary)

                Spacer()

                Link(destination: URL(string: "https://jiacai2050.github.io/")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.circle")
                        Text("Jiacai Liu")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Text("·")
                    .foregroundColor(.secondary.opacity(0.5))

                Link(destination: URL(string: "https://github.com/jiacai2050/x")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text("GitHub")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .font(.caption2)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .frame(minWidth: 700, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $viewModel.showNewDBSheet) {
            NewDatabaseSheet(viewModel: viewModel)
        }
        .sheet(item: $renamingItem) { item in
            VStack(alignment: .leading, spacing: 12) {
                Text("Configure Database Name")
                    .font(.headline)
                Text("Set a custom display name / alias for this database connection.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Database Name", text: $newRecentName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit {
                        if !newRecentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            viewModel.renameRecentDatabase(path: item.path, newName: newRecentName)
                            renamingItem = nil
                        }
                    }

                HStack {
                    Spacer()
                    Button("Cancel") { renamingItem = nil }
                    Button("Save") {
                        viewModel.renameRecentDatabase(path: item.path, newName: newRecentName)
                        renamingItem = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newRecentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
        }
    }
}
