import StatusCore
import StatusUI
import SwiftUI

@main
struct StatusiOSApp: App {
    var body: some Scene {
        WindowGroup {
            IOSRootView()
        }
    }
}

private struct IOSRootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardContainerView(viewModel: makeDashboardViewModel())
                    .navigationTitle("Overview")
            }
            .tabItem {
                Label("Overview", systemImage: "rectangle.grid.2x2")
            }

            NavigationStack {
                DashboardContainerView(viewModel: makeDashboardViewModel())
                    .navigationTitle("Alerts")
            }
            .tabItem {
                Label("Alerts", systemImage: "bell")
            }

            NavigationStack {
                DashboardContainerView(viewModel: makeDashboardViewModel())
                    .navigationTitle("Integrations")
            }
            .tabItem {
                Label("Integrations", systemImage: "puzzlepiece.extension")
            }

            NavigationStack {
                Text("Settings")
                    .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    private func makeDashboardViewModel() -> DashboardViewModel {
        DashboardViewModel {
            try LocalStatusStore.openApplicationSupportStore().dashboardSnapshot()
        }
    }
}
