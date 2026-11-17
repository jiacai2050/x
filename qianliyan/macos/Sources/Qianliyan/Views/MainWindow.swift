import SwiftUI

struct MainWindow: View {
    @Bindable var viewModel: DBViewModel

    var body: some View {
        Group {
            switch viewModel.viewMode {
            case .home:
                HomeView(viewModel: viewModel)
            case .workspace:
                NavigationSplitView {
                    SidebarView(viewModel: viewModel)
                        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
                } detail: {
                    if viewModel.isTableMaximized {
                        ResultTableView(viewModel: viewModel)
                            .id(viewModel.activeTabId)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VSplitView {
                            QueryEditorView(viewModel: viewModel)
                                .frame(minHeight: 100, idealHeight: 150, maxHeight: 300)

                            ResultTableView(viewModel: viewModel)
                                .id(viewModel.activeTabId)
                                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .navigationTitle(windowTitle)
        .sheet(isPresented: $viewModel.showHistory) {
            HistorySheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.selectedTableForDDL) { table in
            DDLSheet(table: table)
        }
        .sheet(isPresented: $viewModel.showAbout) {
            AboutSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowAboutQianliyan"))) { _ in
            viewModel.showAbout = true
        }
    }

    private var windowTitle: String {
        switch viewModel.viewMode {
        case .home:
            return "Qianliyan"
        case .workspace:
            let displayName = viewModel.dbName.isEmpty
                ? (viewModel.dbPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Workspace")
                : viewModel.dbName
            return "Qianliyan - \(displayName)"
        }
    }
}
