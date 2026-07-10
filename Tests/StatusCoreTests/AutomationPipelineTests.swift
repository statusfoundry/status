import Foundation
import Testing
@testable import StatusCore

@Test func automationPipelineRunsMatchingRuleAndPersistsActionAuditTrail() async throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let event = workflowFailedEvent()
    let rule = Rule(
        id: "rul_notify",
        name: "Notify workflow failure",
        enabled: true,
        provider: "github",
        eventType: "github.workflow.failed",
        conditions: [
            RuleCondition(field: "severity", operation: .matchesSeverity, value: .string("warning"))
        ],
        actions: [
            RuleActionDefinition(action: "notification.show", parameters: ["title": "Build failed"])
        ]
    )
    let now = Date(timeIntervalSince1970: 1_783_433_530)
    let runner = ActionRunner(now: { now })
    let dispatcher = RecordingActionEffectDispatcher()
    let pipeline = AutomationPipeline(store: store, actionRunner: runner, effectDispatcher: dispatcher)

    let result = try await pipeline.process(event: event, rules: [rule])

    let actionRun = try #require(result.actionResults.first?.actionRun)
    let auditEntry = try #require(result.actionResults.first?.auditEntry)
    #expect(result.matches.count == 1)
    #expect(try store.actionRun(id: actionRun.id) == actionRun)
    #expect(try store.auditEntry(id: auditEntry.id) == auditEntry)
    let notification = ActionRuntimeNotification(
        title: "Build failed",
        body: event.summary,
        eventID: event.id,
        actionRunID: actionRun.id
    )
    #expect(runner.effects.notifications == [notification])
    #expect(dispatcher.dispatchedEffects == [
        ActionRuntimeEffects(
            notifications: [notification]
        )
    ])
    let notificationRecord = try #require(try store.notification(id: "ntf_\(actionRun.id)"))
    #expect(notificationRecord.eventID == event.id)
    #expect(notificationRecord.statusItemID == "sti_01workflowfailed")
    #expect(notificationRecord.mode == .immediate)
    #expect(notificationRecord.title == "Build failed")
    #expect(notificationRecord.body == event.summary)
    #expect(notificationRecord.deliveredAt != nil)
}

@Test func automationPipelineAppliesStoredNotificationPreferencesBeforeDispatch() async throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let event = workflowFailedEvent()
    let rule = Rule(
        id: "rul_notify",
        name: "Notify workflow failure",
        enabled: true,
        provider: "github",
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [
            RuleActionDefinition(action: "notification.show", parameters: ["title": "Build failed"])
        ]
    )
    let now = Date(timeIntervalSince1970: 1_783_433_530)
    try store.insertEvent(event)
    try store.upsertNotificationPreference(
        NotificationPreference(
            id: "ntp_github_workflow_failed",
            scope: .event,
            pluginID: "github",
            eventType: "github.workflow.failed",
            mode: .dashboardOnly,
            createdAt: now,
            updatedAt: now
        )
    )
    let runner = ActionRunner(now: { now })
    let dispatcher = RecordingActionEffectDispatcher()
    let pipeline = AutomationPipeline(store: store, actionRunner: runner, effectDispatcher: dispatcher)

    let result = try await pipeline.process(event: event, rules: [rule])

    let actionRun = try #require(result.actionResults.first?.actionRun)
    #expect(dispatcher.dispatchedEffects.isEmpty)
    let notificationRecord = try #require(try store.notification(id: "ntf_\(actionRun.id)"))
    #expect(notificationRecord.mode == .dashboardOnly)
    #expect(notificationRecord.deliveredAt == nil)
}

@Test func automationPipelineIgnoresRulesThatDoNotMatch() async throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let event = workflowFailedEvent()
    let rule = Rule(
        id: "rul_jira",
        name: "Jira app review failure",
        enabled: true,
        provider: "appstoreconnect",
        eventType: "app.review.rejected",
        conditions: [],
        actions: [RuleActionDefinition(action: "jira.createIssue")]
    )
    let pipeline = AutomationPipeline(store: store)

    let result = try await pipeline.process(event: event, rules: [rule])

    #expect(result.matches.isEmpty)
    #expect(result.actionResults.isEmpty)
    #expect(try store.auditEntryCount() == 0)
}

@Test func automationPipelineDeniesReviewRequiredActionWithoutWriteGrant() async throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let event = workflowFailedEvent()
    let rule = webhookRule()
    let pipeline = AutomationPipeline(
        store: store,
        actionRunner: ActionRunner(now: { Date(timeIntervalSince1970: 1_783_433_530) })
    )

    let result = try await pipeline.process(event: event, rules: [rule])

    let actionRun = try #require(result.actionResults.first?.actionRun)
    #expect(actionRun.status == .denied)
    #expect(actionRun.error == "webhook.post requires explicit write permission before it can run.")
    #expect(try store.auditEntry(id: "aud_\(actionRun.id)")?.status == "denied")
}

@Test func automationPipelineDispatchesWebhookWhenWriteGrantExists() async throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let event = workflowFailedEvent(provider: "com.status.github")
    let rule = webhookRule(provider: "com.status.github")
    let now = Date(timeIntervalSince1970: 1_783_433_530)
    try installActionPlugin(provider: "com.status.github", store: store, at: now)
    try store.setPluginPermission(pluginID: "com.status.github", permission: .writeActions, granted: true, grantedAt: now)
    let dispatcher = RecordingActionEffectDispatcher()
    let pipeline = AutomationPipeline(
        store: store,
        actionRunner: ActionRunner(now: { now }),
        effectDispatcher: dispatcher
    )

    let result = try await pipeline.process(event: event, rules: [rule])

    let actionRun = try #require(result.actionResults.first?.actionRun)
    let webhookURL = try #require(URL(string: "https://example.com/hooks/status"))
    #expect(actionRun.status == .success)
    #expect(actionRun.result == ["url": webhookURL.absoluteString])
    #expect(try store.auditEntry(id: "aud_\(actionRun.id)")?.status == "success")
    #expect(dispatcher.dispatchedEffects == [
        ActionRuntimeEffects(
            webhooks: [
                ActionRuntimeWebhook(
                    url: webhookURL,
                    payload: [
                        "event_id": event.id,
                        "event_type": event.type,
                        "event_title": event.title,
                        "event_summary": event.summary,
                        "resource_id": event.resourceID,
                        "resource_name": event.resourceName,
                        "severity": event.severity.rawValue,
                        "timestamp": iso8601String(from: event.timestamp)
                    ],
                    actionRunID: actionRun.id
                )
            ]
        )
    ])
}

@Test func automationPipelineMarksWebhookActionFailedWhenDispatchFails() async throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let event = workflowFailedEvent(provider: "com.status.github")
    let rule = webhookRule(provider: "com.status.github")
    let now = Date(timeIntervalSince1970: 1_783_433_530)
    try installActionPlugin(provider: "com.status.github", store: store, at: now)
    try store.setPluginPermission(pluginID: "com.status.github", permission: .writeActions, granted: true, grantedAt: now)
    let pipeline = AutomationPipeline(
        store: store,
        actionRunner: ActionRunner(now: { now }),
        effectDispatcher: FailingActionEffectDispatcher(message: "Webhook endpoint returned 500.")
    )

    await #expect(throws: ActionEffectDispatchFailure.self) {
        _ = try await pipeline.process(event: event, rules: [rule])
    }

    let actionRunID = "run_rul_webhook_evt_01workflowfailed_0"
    let actionRun = try #require(try store.actionRun(id: actionRunID))
    let audit = try #require(try store.auditEntry(id: "aud_\(actionRunID)"))
    #expect(actionRun.status == .failed)
    #expect(actionRun.error == "Webhook endpoint returned 500.")
    #expect(audit.status == "failed")
    #expect(audit.detail == "Runtime effect dispatch failed for webhook.post. Webhook endpoint returned 500.")
}

@Test func automationPipelineExecutesProviderBackedAction() async throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_530)
    let event = workflowFailedEvent(provider: "com.status.jira")
    let rule = Rule(
        id: "rul_create_jira",
        name: "Create Jira issue",
        enabled: true,
        provider: "com.status.jira",
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [
            RuleActionDefinition(action: "jira.createIssue", parameters: ["summary": "{{event.title}}"])
        ]
    )
    try installActionPlugin(
        provider: "com.status.jira",
        store: store,
        at: now,
        actions: [
            PackagedPluginAction(id: "jira.createIssue", label: "Create issue", requiresWritePermission: true, request: "create_issue")
        ],
        requests: PackagedPluginRequests(requests: [
            "create_issue": PackagedPluginRequest(method: "POST", url: "https://example.atlassian.net/rest/api/3/issue")
        ])
    )
    try store.setPluginPermission(pluginID: "com.status.jira", permission: .writeActions, granted: true, grantedAt: now)
    let executor = RecordingProviderActionExecutor(result: ["issue_key": "STATUS-1"])
    let pipeline = AutomationPipeline(
        store: store,
        actionRunner: ActionRunner(now: { now }),
        providerActionExecutor: executor
    )

    let result = try await pipeline.process(event: event, rules: [rule])

    let actionRun = try #require(result.actionResults.first?.actionRun)
    let storedActionRun = try #require(try store.actionRun(id: actionRun.id))
    #expect(storedActionRun.status == .success)
    #expect(storedActionRun.result == ["issue_key": "STATUS-1"])
    #expect(executor.actions == [
        ActionRuntimeProviderAction(
            actionRunID: actionRun.id,
            action: "jira.createIssue",
            targetProvider: "com.status.jira",
            provider: event.provider,
            parameters: ["summary": "Workflow failed"],
            event: event
        )
    ])
}

@Test func automationPipelineRoutesCrossAppProviderActionToDeclaringPlugin() async throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_530)
    let event = workflowFailedEvent(provider: "com.status.github")
    let rule = Rule(
        id: "rul_github_to_jira",
        name: "Failed workflow creates Jira issue",
        enabled: true,
        provider: "com.status.github",
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [
            RuleActionDefinition(action: "jira.createIssue", parameters: ["summary": "{{event.title}}"])
        ]
    )
    try installActionPlugin(
        provider: "com.status.jira",
        store: store,
        at: now,
        actions: [
            PackagedPluginAction(id: "jira.createIssue", label: "Create issue", requiresWritePermission: true, request: "create_issue")
        ],
        requests: PackagedPluginRequests(requests: [
            "create_issue": PackagedPluginRequest(method: "POST", url: "https://example.atlassian.net/rest/api/3/issue")
        ])
    )
    try store.setPluginPermission(pluginID: "com.status.jira", permission: .writeActions, granted: true, grantedAt: now)
    let executor = RecordingProviderActionExecutor(result: ["issue_key": "STATUS-2"])
    let pipeline = AutomationPipeline(
        store: store,
        actionRunner: ActionRunner(now: { now }),
        providerActionExecutor: executor
    )

    let result = try await pipeline.process(event: event, rules: [rule])

    let actionRun = try #require(result.actionResults.first?.actionRun)
    #expect(executor.actions == [
        ActionRuntimeProviderAction(
            actionRunID: actionRun.id,
            action: "jira.createIssue",
            targetProvider: "com.status.jira",
            provider: "com.status.github",
            parameters: ["summary": "Workflow failed"],
            event: event
        )
    ])
}

@Test func automationPipelineExecutesDeclaredThirdPartyProviderAction() async throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_530)
    let event = workflowFailedEvent(provider: "com.example.linear")
    let rule = Rule(
        id: "rul_create_linear",
        name: "Create Linear issue",
        enabled: true,
        provider: "com.example.linear",
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [
            RuleActionDefinition(action: "linear.createIssue", parameters: ["title": "{{event.title}}"])
        ]
    )
    try installActionPlugin(
        provider: "com.example.linear",
        store: store,
        at: now,
        actions: [
            PackagedPluginAction(id: "linear.createIssue", label: "Create issue", requiresWritePermission: true, request: "create_issue")
        ],
        requests: PackagedPluginRequests(requests: [
            "create_issue": PackagedPluginRequest(method: "POST", url: "https://api.linear.app/graphql")
        ])
    )
    try store.setPluginPermission(pluginID: "com.example.linear", permission: .writeActions, granted: true, grantedAt: now)
    let executor = RecordingProviderActionExecutor(result: ["issue_id": "LIN-1"])
    let pipeline = AutomationPipeline(
        store: store,
        actionRunner: ActionRunner(now: { now }),
        providerActionExecutor: executor
    )

    let result = try await pipeline.process(event: event, rules: [rule])

    let actionRun = try #require(result.actionResults.first?.actionRun)
    let storedActionRun = try #require(try store.actionRun(id: actionRun.id))
    #expect(storedActionRun.status == .success)
    #expect(storedActionRun.result == ["issue_id": "LIN-1"])
    #expect(executor.actions == [
        ActionRuntimeProviderAction(
            actionRunID: actionRun.id,
            action: "linear.createIssue",
            targetProvider: "com.example.linear",
            provider: event.provider,
            parameters: ["title": "Workflow failed"],
            event: event
        )
    ])
}

@Test func actionWebhookRequestBuilderCreatesJSONPostRequest() throws {
    let url = try #require(URL(string: "https://example.com/hooks/status"))
    let request = try ActionWebhookRequestBuilder().request(
        for: ActionRuntimeWebhook(
            url: url,
            payload: [
                "event_id": "evt_01",
                "severity": "warning"
            ]
        )
    )

    let body = try #require(request.body)
    let decoded = try JSONDecoder().decode([String: String].self, from: body)
    #expect(request.method == "POST")
    #expect(request.url == url)
    #expect(request.headers["Content-Type"] == "application/json")
    #expect(request.headers["Accept"] == "application/json")
    #expect(request.headers["User-Agent"] == "Status/0.1")
    #expect(request.timeoutSeconds == 30)
    #expect(decoded == ["event_id": "evt_01", "severity": "warning"])
}

private struct FailingActionEffectDispatcher: ActionEffectDispatcher {
    var message: String

    func dispatch(_ effects: ActionRuntimeEffects) async throws {
        guard let actionRunID = effects.webhooks.first?.actionRunID else {
            return
        }
        throw ActionEffectDispatchFailure(actionRunID: actionRunID, message: message)
    }
}

private final class RecordingProviderActionExecutor: ProviderActionExecutor, @unchecked Sendable {
    var actions: [ActionRuntimeProviderAction] = []
    var result: [String: String]

    init(result: [String: String]) {
        self.result = result
    }

    func execute(_ action: ActionRuntimeProviderAction) async throws -> [String: String] {
        actions.append(action)
        return result
    }
}

@Test func automationPipelineCanEvaluateStoredRules() async throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let event = workflowFailedEvent()
    let rule = Rule(
        id: "rul_notify",
        name: "Notify workflow failure",
        enabled: true,
        provider: "github",
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [
            RuleActionDefinition(action: "notification.show")
        ]
    )
    try store.upsertRule(rule, updatedAt: event.timestamp)
    let pipeline = AutomationPipeline(
        store: store,
        actionRunner: ActionRunner(now: { Date(timeIntervalSince1970: 1_783_433_530) })
    )

    let result = try await pipeline.processStoredRules(for: event)

    #expect(result.matches.map(\.rule.id) == ["rul_notify"])
    #expect(result.actionResults.first?.actionRun.action == "notification.show")
    #expect(try store.actionRun(id: "run_rul_notify_evt_01workflowfailed_0")?.status == .success)
}

private func webhookRule(provider: String = "github") -> Rule {
    Rule(
        id: "rul_webhook",
        name: "Webhook workflow failure",
        enabled: true,
        provider: provider,
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [
            RuleActionDefinition(action: "webhook.post", parameters: ["url": "https://example.com/hooks/status"])
        ]
    )
}

private func workflowFailedEvent(provider: String = "github") -> Event {
    Event(
        id: "evt_01workflowfailed",
        provider: provider,
        type: "github.workflow.failed",
        resourceID: "res_status_repo",
        resourceName: "status",
        severity: .critical,
        title: "Workflow failed",
        summary: "CI failed on main.",
        timestamp: Date(timeIntervalSince1970: 1_783_433_520),
        actionURL: URL(string: "https://github.com/statusfoundry/status/actions"),
        fingerprint: "github:workflow.failed:res_status_repo:failure"
    )
}

private func iso8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

private func installActionPlugin(
    provider: String,
    store: StatusPersistenceStore,
    at date: Date,
    actions: [PackagedPluginAction] = [],
    requests: PackagedPluginRequests = PackagedPluginRequests()
) throws {
    let hasRequests = requests.requests.isEmpty == false
    let packagePath = try actionPluginPackagePath(provider: provider, actions: actions, requests: requests)
    let manifest = PluginManifest(
        id: provider,
        name: provider,
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "automation",
        description: "Automation fixture.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: hasRequests ? [.network, .userConfiguredDomains, .writeActions] : [.writeActions],
        domains: []
    )
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: "/tmp/\(provider)",
            packagePath: packagePath,
            verification: PluginPackageVerificationResult(
                pluginID: provider,
                version: manifest.version,
                sha256: "fixture",
                signedBy: "status-foundry-dev"
            ),
            packageDefinition: PluginPackageDefinition(requests: requests, actions: actions),
            installedAt: date
        )
    )
}

private func actionPluginPackagePath(
    provider: String,
    actions: [PackagedPluginAction],
    requests: PackagedPluginRequests
) throws -> String? {
    guard actions.isEmpty == false || requests.requests.isEmpty == false else {
        return nil
    }
    var files: [(String, Data)] = []
    if requests.requests.isEmpty == false {
        let requestObjects = requests.requests.mapValues { request in
            [
                "method": request.method,
                "url": request.url
            ]
        }
        files.append((
            "requests.json",
            try JSONSerialization.data(withJSONObject: ["requests": requestObjects], options: [.sortedKeys])
        ))
    }
    if actions.isEmpty == false {
        let actionObjects = actions.map { action in
            [
                "id": action.id,
                "label": action.label,
                "requiresWritePermission": action.requiresWritePermission,
                "request": action.request
            ] as [String: Any]
        }
        files.append((
            "actions.json",
            try JSONSerialization.data(withJSONObject: ["actions": actionObjects], options: [.sortedKeys])
        ))
    }
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(provider)-\(UUID().uuidString).statusplugin.zip")
    try automationStoredZip(files: files).write(to: packageURL)
    return packageURL.path
}

private func temporaryDatabase() throws -> SQLiteDatabase {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-\(UUID().uuidString).sqlite")
        .path
    return try SQLiteDatabase(path: path)
}

private func automationStoredZip(files: [(String, Data)]) -> Data {
    var archive = Data()
    var centralDirectory = Data()
    var offset: UInt32 = 0

    for (name, data) in files {
        let nameData = Data(name.utf8)
        var localHeader = Data()
        localHeader.appendUInt32LE(0x0403_4b50)
        localHeader.appendUInt16LE(20)
        localHeader.appendUInt16LE(0)
        localHeader.appendUInt16LE(0)
        localHeader.appendUInt16LE(0)
        localHeader.appendUInt16LE(0)
        localHeader.appendUInt32LE(0)
        localHeader.appendUInt32LE(UInt32(data.count))
        localHeader.appendUInt32LE(UInt32(data.count))
        localHeader.appendUInt16LE(UInt16(nameData.count))
        localHeader.appendUInt16LE(0)
        localHeader.append(nameData)

        var centralHeader = Data()
        centralHeader.appendUInt32LE(0x0201_4b50)
        centralHeader.appendUInt16LE(20)
        centralHeader.appendUInt16LE(20)
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt32LE(0)
        centralHeader.appendUInt32LE(UInt32(data.count))
        centralHeader.appendUInt32LE(UInt32(data.count))
        centralHeader.appendUInt16LE(UInt16(nameData.count))
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt32LE(0)
        centralHeader.appendUInt32LE(offset)
        centralHeader.append(nameData)

        archive.append(localHeader)
        archive.append(data)
        centralDirectory.append(centralHeader)
        offset += UInt32(localHeader.count + data.count)
    }

    let centralOffset = UInt32(archive.count)
    archive.append(centralDirectory)
    archive.appendUInt32LE(0x0605_4b50)
    archive.appendUInt16LE(0)
    archive.appendUInt16LE(0)
    archive.appendUInt16LE(UInt16(files.count))
    archive.appendUInt16LE(UInt16(files.count))
    archive.appendUInt32LE(UInt32(centralDirectory.count))
    archive.appendUInt32LE(centralOffset)
    archive.appendUInt16LE(0)
    return archive
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
