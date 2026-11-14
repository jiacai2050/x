import SwiftUI
import AppKit

final class WindowDelegate: NSObject, NSWindowDelegate {
    private var isCurrentlyZoomed = false
    private var normalFrame: NSRect = NSRect(x: 200, y: 150, width: 1000, height: 650)
    private var isTransitioning = false

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        let screenVisible = window.screen?.visibleFrame ?? .zero

        // Accurately check if window is at maximized size
        let isMaximizedNow = abs(window.frame.width - screenVisible.width) < 20 &&
                             abs(window.frame.height - screenVisible.height) < 40

        isTransitioning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.isTransitioning = false
        }

        if isCurrentlyZoomed || isMaximizedNow {
            // Currently maximized -> restore to normal size
            window.setFrame(normalFrame, display: true, animate: true)
            isCurrentlyZoomed = false
            return false
        } else {
            // Currently normal size -> save frame and zoom to full
            normalFrame = window.frame
            isCurrentlyZoomed = true
            return true
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard !isTransitioning, let window = notification.object as? NSWindow else { return }
        let screenVisible = window.screen?.visibleFrame ?? .zero
        let isMaximized = abs(window.frame.width - screenVisible.width) < 20 &&
                          abs(window.frame.height - screenVisible.height) < 40

        if !isMaximized {
            normalFrame = window.frame
            isCurrentlyZoomed = false
        } else {
            isCurrentlyZoomed = true
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowDelegate = WindowDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force app to be a regular GUI application with Dock icon and menu bar
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first {
            window.delegate = windowDelegate
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct QianliyanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel = DBViewModel()

    var body: some Scene {
        WindowGroup {
            MainWindow(viewModel: viewModel)
                .frame(minWidth: 850, minHeight: 550)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Qianliyan") {
                    viewModel.showAbout = true
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("Open Database...") {
                    viewModel.openFromPicker()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("New Database...") {
                    viewModel.createNewDatabase()
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("New Query Tab") {
                    viewModel.newTab()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(viewModel.viewMode != .workspace)

                Button("Close Tab") {
                    viewModel.closeTab(id: viewModel.activeTabId)
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(viewModel.viewMode != .workspace || viewModel.tabs.count <= 1)

                Divider()

                Button("Import Connections...") {
                    viewModel.importConnections()
                }

                Button("Export Connections...") {
                    viewModel.exportConnections()
                }

                Divider()

                Button("Close Database") {
                    viewModel.backToHome()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(viewModel.viewMode != .workspace)
            }

            CommandMenu("Query") {
                Button("Run Query") {
                    viewModel.executeQuery()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.viewMode != .workspace || viewModel.activeTab.isExecuting)

                Button("Cancel Query") {
                    viewModel.cancelQuery()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(viewModel.viewMode != .workspace || !viewModel.activeTab.isExecuting)

                Divider()

                Button("Refresh Schema") {
                    viewModel.refreshSchema()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.viewMode != .workspace)

                Button("Query History...") {
                    viewModel.showHistory = true
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(viewModel.viewMode != .workspace)
            }
        }
    }
}
