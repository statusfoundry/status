import StatusCore
import StatusUI
import SwiftUI

@main
struct StatusMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacRootView()
        }
        .windowStyle(.titleBar)
    }
}

private struct MacRootView: View {
    var body: some View {
        NavigationSplitView {
            List(selection: .constant("overview")) {
                NavigationLink(value: "overview") {
                    Label("Overview", systemImage: "rectangle.grid.2x2")
                }
                NavigationLink(value: "integrations") {
                    Label("Integrations", systemImage: "puzzlepiece.extension")
                }
                NavigationLink(value: "audit") {
                    Label("Audit Log", systemImage: "list.bullet.rectangle")
                }
                NavigationLink(value: "settings") {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .navigationTitle("Status")
        } detail: {
            DashboardContainerView(viewModel: makeDashboardViewModel())
                .navigationTitle("Overview")
        }
    }

    private func makeDashboardViewModel() -> DashboardViewModel {
        DashboardViewModel {
            try LocalStatusStore.openApplicationSupportStore().dashboardSnapshot()
        }
    }
}
