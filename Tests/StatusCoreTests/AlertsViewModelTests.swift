import Foundation
import Testing
import StatusCore
@testable import StatusUI

@MainActor
@Test func alertsViewModelRunsLifecycleActionsAndReloadsItems() throws {
    let first = statusItem(id: "sti_first")
    let second = statusItem(id: "sti_second")
    var loadedItems = [first, second]
    var resolvedIDs: [String] = []
    var snoozedIDs: [String] = []
    var dismissedIDs: [String] = []
    var reloadCount = 0
    let viewModel = AlertsViewModel(
        loadItems: {
            reloadCount += 1
            return loadedItems
        },
        resolveItem: { item in
            resolvedIDs.append(item.id)
            loadedItems.removeAll { $0.id == item.id }
        },
        snoozeItem: { item in
            snoozedIDs.append(item.id)
        },
        dismissItem: { item in
            dismissedIDs.append(item.id)
            loadedItems.removeAll { $0.id == item.id }
        }
    )

    viewModel.reload()
    #expect(viewModel.items.map(\.id) == ["sti_first", "sti_second"])

    viewModel.resolve(first)
    #expect(resolvedIDs == ["sti_first"])
    #expect(viewModel.items.map(\.id) == ["sti_second"])

    viewModel.snooze(second)
    #expect(snoozedIDs == ["sti_second"])
    #expect(viewModel.items.map(\.id) == ["sti_second"])

    viewModel.dismiss(second)
    #expect(dismissedIDs == ["sti_second"])
    #expect(viewModel.items.isEmpty)
    #expect(reloadCount == 4)
}

@MainActor
@Test func alertsViewModelKeepsCurrentItemsAndReportsActionErrors() throws {
    let item = statusItem(id: "sti_error")
    let viewModel = AlertsViewModel(
        initialItems: [item],
        loadItems: { [item] },
        resolveItem: { _ in throw TestActionError.failed }
    )

    viewModel.resolve(item)

    #expect(viewModel.items == [item])
    #expect(viewModel.loadError == "failed")
}

private func statusItem(id: String) -> StatusItem {
    StatusItem(
        id: id,
        resourceID: "res_1",
        severity: .critical,
        title: "Website down",
        summary: "The monitored website is not responding.",
        state: .open,
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
}

private enum TestActionError: Error, LocalizedError {
    case failed

    var errorDescription: String? {
        "failed"
    }
}
