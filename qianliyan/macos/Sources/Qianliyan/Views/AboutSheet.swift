import SwiftUI
import AppKit

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "nightly"
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "native"
        #endif
        return "Version \(version) (macOS \(arch))"
    }

    var body: some View {
        VStack(spacing: 20) {
            // App Icon & Name
            VStack(spacing: 8) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .cornerRadius(16)
                } else {
                    Image(systemName: "eye.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.accentColor)
                }

                Text("Qianliyan (千里眼)")
                    .font(.title.bold())

                Text("Modern Native Database Client")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(appVersionString)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.top, 10)

            Divider()

            // Description & Tech Stack
            VStack(spacing: 8) {
                Text("A lightweight, ultra-fast native database client powered by a Zig core engine and modern SwiftUI.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            // Links Section
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .foregroundColor(.blue)
                        .font(.body)

                    Text("Author:")
                        .font(.caption.bold())

                    Link("Jiacai Liu", destination: URL(string: "https://jiacai2050.github.io/")!)
                        .font(.caption)

                    Text("(https://jiacai2050.github.io/)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .foregroundColor(.orange)
                        .font(.caption)

                    Text("GitHub:")
                        .font(.caption.bold())

                    Link("jiacai2050/x", destination: URL(string: "https://github.com/jiacai2050/x")!)
                        .font(.caption)

                    Text("(https://github.com/jiacai2050/x)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .padding(.horizontal, 16)

            Spacer()

            // Footer Button
            HStack {
                Text("© 2026 Jiacai Liu. All rights reserved.")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(width: 440, height: 380)
    }
}
