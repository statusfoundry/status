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

@MainActor
@Test func notificationPreferencesViewModelResolvesInheritedAndExplicitModes() throws {
    let workflowEvent = NotificationPreferenceEventRow(
        type: "github.workflow.failed",
        label: "Workflow failed",
        defaultMode: .dashboardOnly
    )
    let group = NotificationPreferencePluginGroup(id: "github", name: "GitHub", events: [workflowEvent])
    var preferences = [
        NotificationPreference(
            id: "ntp_github",
            scope: .plugin,
            pluginID: "github",
            mode: .digest,
            createdAt: Date(timeIntervalSince1970: 1_783_433_520),
            updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
        )
    ]
    var saved: [(pluginID: String, accountID: String?, eventType: String?, mode: NotificationMode?)] = []
    let viewModel = NotificationPreferencesViewModel(
        loadPluginGroups: { [group] },
        loadPreferences: { preferences },
        setPreference: { pluginID, accountID, eventType, mode in
            saved.append((pluginID, accountID, eventType, mode))
            if let mode {
                preferences.append(
                    NotificationPreference(
                        id: "ntp_event",
                        scope: .event,
                        pluginID: pluginID,
                        accountID: accountID,
                        eventType: eventType,
                        mode: mode,
                        createdAt: Date(timeIntervalSince1970: 1_783_433_520),
                        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
                    )
                )
            } else {
                preferences.removeAll { $0.pluginID == pluginID && $0.eventType == eventType }
            }
        }
    )

    viewModel.reload()

    #expect(viewModel.pluginGroups == [group])
    #expect(viewModel.explicitMode(pluginID: "github") == .digest)
    #expect(viewModel.effectiveMode(pluginID: "github", event: workflowEvent) == .digest)

    viewModel.setMode(.immediate, pluginID: "github", eventType: workflowEvent.type)

    #expect(saved.count == 1)
    #expect(saved[0].pluginID == "github")
    #expect(saved[0].accountID == nil)
    #expect(saved[0].eventType == workflowEvent.type)
    #expect(saved[0].mode == .immediate)
    #expect(viewModel.effectiveMode(pluginID: "github", event: workflowEvent) == .immediate)

    viewModel.setMode(nil, pluginID: "github", eventType: workflowEvent.type)

    #expect(saved.count == 2)
    #expect(saved[1].mode == nil)
    #expect(viewModel.effectiveMode(pluginID: "github", event: workflowEvent) == .digest)
}

@MainActor
@Test func notificationHistoryViewModelLoadsAndReportsErrors() throws {
    let notification = NotificationRecord(
        id: "ntf_01",
        eventID: "evt_01",
        statusItemID: "sti_01",
        mode: .dashboardOnly,
        title: "Build failed",
        body: "CI failed on main.",
        createdAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    var shouldFail = false
    let viewModel = NotificationHistoryViewModel {
        if shouldFail {
            throw TestActionError.failed
        }
        return [notification]
    }

    viewModel.reload()

    #expect(viewModel.notifications == [notification])
    #expect(viewModel.loadError == nil)

    shouldFail = true
    viewModel.reload()

    #expect(viewModel.notifications.isEmpty)
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
