import SwiftUI
import AppKit

struct NewDatabaseSheet: View {
    @Bindable var viewModel: DBViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var dbName: String = ""
    @State private var filePath: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Database")
                        .font(.headline)
                    Text("Create a new SQLite database with custom alias and storage path.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(.bar)

            Divider()

            // Form
            VStack(alignment: .leading, spacing: 18) {
                // Database Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Database Name / Alias")
                        .font(.subheadline.bold())
                    TextField("e.g. My App DB, Development", text: $dbName)
                        .textFieldStyle(.roundedBorder)
                    Text("A friendly display name used across Qianliyan.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // File Path
                VStack(alignment: .leading, spacing: 6) {
                    Text("File Location")
                        .font(.subheadline.bold())

                    HStack {
                        TextField("No file selected", text: $filePath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)

                        Button("Browse...") {
                            chooseFileLocation()
                        }
                    }
                    Text("Where the SQLite file will be created on disk.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)

            Spacer()

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }

                Button("Create Database") {
                    createAndOpen()
                }
                .buttonStyle(.borderedProminent)
                .disabled(filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)
        }
        .frame(width: 480, height: 320)
    }

    private func chooseFileLocation() {
        let panel = NSSavePanel()
        panel.showsTagField = false // Hide macOS Finder tags field
        panel.allowedContentTypes = []
        let sanitizedName = dbName.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        panel.nameFieldStringValue = sanitizedName.isEmpty ? "new_database.sqlite" : "\(sanitizedName).sqlite"
        panel.prompt = "Save Here"

        if panel.runModal() == .OK, let url = panel.url {
            self.filePath = url.path
            if dbName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                dbName = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func createAndOpen() {
        let trimmedPath = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        let trimmedName = dbName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? URL(fileURLWithPath: trimmedPath).deletingPathExtension().lastPathComponent : trimmedName

        dismiss()
        viewModel.openDatabase(path: trimmedPath, name: finalName)
    }
}
