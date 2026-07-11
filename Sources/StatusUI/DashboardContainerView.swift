import StatusCore
import SwiftUI

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var snapshot: DashboardSnapshot
    @Published public private(set) var loadError: String?
    @Published public private(set) var isRefreshingApps: Bool
    @Published public private(set) var refreshResult: String?
    @Published public private(set) var refreshError: String?

    private let loadSnapshot: () throws -> DashboardSnapshot
    private let refreshApps: (() async throws -> String)?

    public init(
        initialSnapshot: DashboardSnapshot = .empty,
        loadSnapshot: @escaping () throws -> DashboardSnapshot,
        refreshApps: (() async throws -> String)? = nil
    ) {
        self.snapshot = initialSnapshot
        self.isRefreshingApps = false
        self.refreshResult = nil
        self.refreshError = nil
        self.loadSnapshot = loadSnapshot
        self.refreshApps = refreshApps
    }

    public func reload() {
        do {
            snapshot = try loadSnapshot()
            loadError = nil
        } catch {
            snapshot = .empty
            loadError = error.localizedDescription
        }
    }

    public func refreshConfiguredApps() async {
        guard isRefreshingApps == false, let refreshApps else { return }
        isRefreshingApps = true
        refreshResult = nil
        refreshError = nil
        defer { isRefreshingApps = false }

        do {
            refreshResult = try await refreshApps()
            reload()
        } catch {
            refreshError = error.localizedDescription
            reload()
        }
    }
}

public struct DashboardContainerView: View {
    @StateObject private var viewModel: DashboardViewModel
    private let reloadToken: Int
    private let openApp: ((IntegrationSummary) -> Void)?

    public init(
        viewModel: @autoclosure @escaping () -> DashboardViewModel,
        reloadToken: Int = 0,
        openApp: ((IntegrationSummary) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.reloadToken = reloadToken
        self.openApp = openApp
    }

    public var body: some View {
        DashboardView(
            snapshot: viewModel.snapshot,
            isRefreshingApps: viewModel.isRefreshingApps,
            refreshResult: viewModel.refreshResult,
            refreshError: viewModel.refreshError,
            refreshApps: viewModel.refreshConfiguredApps,
            openApp: openApp
        )
            .overlay(alignment: .bottom) {
                if let loadError = viewModel.loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(10)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
            }
            .task(id: reloadToken) {
                viewModel.reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: .statusConfiguredAppsDidChange)) { _ in
                viewModel.reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: .statusAppDataDidChange)) { _ in
                viewModel.reload()
            }
            .refreshable {
                viewModel.reload()
            }
    }
}
