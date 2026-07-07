import StatusCore
import SwiftUI

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var snapshot: DashboardSnapshot
    @Published public private(set) var loadError: String?

    private let loadSnapshot: () throws -> DashboardSnapshot

    public init(
        initialSnapshot: DashboardSnapshot = .empty,
        loadSnapshot: @escaping () throws -> DashboardSnapshot
    ) {
        self.snapshot = initialSnapshot
        self.loadSnapshot = loadSnapshot
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
}

public struct DashboardContainerView: View {
    @StateObject private var viewModel: DashboardViewModel

    public init(viewModel: @autoclosure @escaping () -> DashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    public var body: some View {
        DashboardView(snapshot: viewModel.snapshot)
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
            .task {
                viewModel.reload()
            }
            .refreshable {
                viewModel.reload()
            }
    }
}
