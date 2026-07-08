import Foundation
import Testing
@testable import StatusCore

@Test func migrationCreatesExpectedTablesAndUserVersion() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)

    let tableRows = try database.query(
        """
        SELECT name FROM sqlite_master
        WHERE type = 'table'
        ORDER BY name
        """
    )
    let tableNames = Set(try tableRows.map { try $0.requiredText("name") })

    #expect(tableNames.contains("plugins"))
    #expect(tableNames.contains("accounts"))
    #expect(tableNames.contains("resources"))
    #expect(tableNames.contains("events"))
    #expect(tableNames.contains("status_items"))
    #expect(tableNames.contains("resource_state_snapshots"))
    #expect(tableNames.contains("rules"))
    #expect(tableNames.contains("audit_entries"))
    #expect(tableNames.contains("sync_state"))

    let userVersion = try database.query("PRAGMA user_version").first?["user_version"]
    #expect(userVersion == .integer(Int64(StatusDatabaseMigrator.currentUserVersion)))
}

@Test func schemaDoesNotCreateSecretColumns() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)

    let rows = try database.query(
        """
        SELECT name FROM pragma_table_info('accounts')
        UNION ALL
        SELECT name FROM pragma_table_info('triggers')
        """
    )
    let columns = try rows.map { try $0.requiredText("name") }

    #expect(columns.contains("credential_ref"))
    #expect(columns.contains("secret_ref"))
    #expect(columns.contains("token") == false)
    #expect(columns.contains("password") == false)
    #expect(columns.contains("private_key") == false)
    #expect(columns.contains("secret") == false)
}

@Test func eventStatusItemAndAuditEntryRoundTripThroughSQLite() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let url = try #require(URL(string: "https://github.com/statusfoundry/status/actions"))

    let event = Event(
        id: "evt_01workflowfailed",
        provider: "github",
        type: "github.workflow.failed",
        resourceID: "res_status_repo",
        resourceName: "status",
        severity: .critical,
        title: "Workflow failed",
        summary: "CI failed on main.",
        timestamp: now,
        actionURL: url,
        fingerprint: "github:workflow.failed:res_status_repo:failure"
    )
    let statusItem = StatusItem(
        id: "sti_01workflowfailed",
        resourceID: "res_status_repo",
        severity: .critical,
        title: "GitHub workflow failed",
        summary: "The main branch build failed.",
        state: .open,
        updatedAt: now,
        actionLink: ActionLink(id: "act_open_workflow", label: "Open workflow", url: url)
    )
    let auditEntry = AuditEntry(
        id: "aud_01notification",
        title: "Notification queued",
        detail: "Rule matched github.workflow.failed and queued a local notification.",
        timestamp: now,
        status: "success",
        eventID: event.id,
        actionRunID: "run_01notification"
    )

    try store.insertEvent(event)
    try store.insertStatusItem(statusItem)
    try store.insertAuditEntry(auditEntry)

    #expect(try store.event(id: event.id) == event)
    #expect(try store.statusItem(id: statusItem.id)?.title == statusItem.title)
    #expect(try store.statusItem(id: statusItem.id)?.actionLink?.url == url)
    #expect(try store.auditEntry(id: auditEntry.id) == auditEntry)
}

@Test func statusItemLifecycleVerbsPersistAndFilterInboxItems() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let snoozeUntil = now.addingTimeInterval(3_600)
    let item = StatusItem(
        id: "sti_lifecycle",
        resourceID: "res_status_repo",
        severity: .warning,
        title: "Workflow failed",
        summary: "The build failed.",
        state: .open,
        updatedAt: now
    )

    try store.insertStatusItem(item)
    try store.snoozeStatusItem(id: item.id, until: snoozeUntil, at: now.addingTimeInterval(60))

    let snoozed = try #require(try store.statusItem(id: item.id))
    #expect(snoozed.state == .snoozed)
    #expect(snoozed.snoozeUntil == snoozeUntil)
    #expect(try store.statusItems().map(\.id) == [item.id])

    let reopened = try store.reopenExpiredSnoozedItems(at: snoozeUntil.addingTimeInterval(1))
    #expect(reopened.map(\.id) == [item.id])
    let open = try #require(try store.statusItem(id: item.id))
    #expect(open.state == .open)
    #expect(open.snoozeUntil == nil)

    try store.resolveStatusItem(id: item.id, at: snoozeUntil.addingTimeInterval(120))
    let resolved = try #require(try store.statusItem(id: item.id))
    #expect(resolved.state == .resolved)
    #expect(resolved.resolvedAt == snoozeUntil.addingTimeInterval(120))
    #expect(try store.statusItems().isEmpty)
}

@Test func dismissStatusItemPersistsReasonAndLeavesInbox() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let item = StatusItem(
        id: "sti_dismiss",
        resourceID: "res_status_repo",
        severity: .warning,
        title: "Workflow failed",
        summary: "The build failed.",
        state: .open,
        updatedAt: now
    )

    try store.insertStatusItem(item)
    try store.dismissStatusItem(id: item.id, reason: "Handled in GitHub", at: now.addingTimeInterval(60))

    let dismissed = try #require(try store.statusItem(id: item.id))
    #expect(dismissed.state == .dismissed)
    #expect(dismissed.dismissedReason == "Handled in GitHub")
    #expect(dismissed.resolvedAt == now.addingTimeInterval(60))
    #expect(try store.statusItems().isEmpty)
}

@Test func jobAuditEntryIncludesJobProvenance() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let job = JobRecord(
        id: "job_poll_01",
        pluginID: "com.status.github",
        triggerID: "trg_github",
        status: .success,
        queuedAt: now.addingTimeInterval(-5),
        startedAt: now.addingTimeInterval(-3),
        finishedAt: now,
        emittedEventIDs: ["evt_workflow_failed"]
    )

    try store.insertJobAuditEntry(for: job, timestamp: now)

    #expect(
        try store.auditEntry(id: "aud_job_poll_01_success") == AuditEntry(
            id: "aud_job_poll_01_success",
            title: "Job completed",
            detail: "com.status.github job job_poll_01 from trigger trg_github is success. Emitted events: evt_workflow_failed.",
            timestamp: now,
            status: "success",
            jobID: job.id,
            eventID: "evt_workflow_failed"
        )
    )
}

@Test func actionRunRoundTripsThroughSQLite() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let actionRun = ActionRunRecord(
        id: "run_rul_notify_evt_01_0",
        ruleID: "rul_notify",
        eventID: "evt_01",
        action: "notification.show",
        status: .success,
        input: ["title": "Build failed"],
        result: ["delivered": "local"],
        startedAt: now,
        finishedAt: now.addingTimeInterval(1)
    )

    try store.upsertActionRun(actionRun)

    #expect(try store.actionRun(id: actionRun.id) == actionRun)
}

@Test func ruleRoundTripsThroughSQLite() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let rule = Rule(
        id: "rul_notify",
        name: "Notify workflow failure",
        enabled: true,
        provider: "github",
        eventType: "github.workflow.failed",
        conditions: [
            RuleCondition(field: "severity", operation: .matchesSeverity, value: .string("warning")),
            RuleCondition(field: "resourceName", operation: .contains, value: .string("status"))
        ],
        actions: [
            RuleActionDefinition(action: "notification.show", parameters: ["title": "Build failed"])
        ]
    )

    try store.upsertRule(rule, updatedAt: now)

    #expect(try store.rule(id: rule.id) == rule)
    #expect(try store.rules() == [rule])
    #expect(try store.rules(eventType: "github.workflow.failed") == [rule])
    #expect(try store.rules(eventType: "app.review.rejected").isEmpty)
}

@Test func resourceStateSnapshotRoundTripsThroughSQLite() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    try insertResourceFixture(database, resourceID: "res_app")
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let snapshot = ResourceStateSnapshot(
        resourceID: "res_app",
        state: [
            "appStoreState": "REJECTED",
            "latestBuildState": "VALID"
        ],
        stateHash: "hash_01",
        jobID: "job_01poll",
        capturedAt: now
    )

    try store.upsertResourceStateSnapshot(snapshot)

    #expect(try store.resourceStateSnapshot(resourceID: "res_app") == snapshot)
}

@Test func accountConfigurationRoundTripsThroughSyncState() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    try insertPluginFixture(database, pluginID: "com.status.website")
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let configuration = PluginAccountConfiguration(
        id: "acct_website_status_registry",
        pluginID: "com.status.website",
        accountName: "status-registry.hakobs.com",
        variables: ["host": "status-registry.hakobs.com"]
    )

    try store.upsertAccountConfiguration(configuration, updatedAt: now)

    #expect(try store.account(id: configuration.id)?.displayName == "status-registry.hakobs.com")
    #expect(try store.accountConfiguration(accountID: configuration.id) == configuration)
    #expect(try store.accountConfigurations(pluginID: "com.status.website") == [configuration])
}

@Test func emptyDashboardSnapshotUsesLocalFirstEmptyState() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)

    let snapshot = try store.dashboardSnapshot()

    #expect(snapshot == .empty)
}

@Test func dashboardSnapshotReadsPersistedRows() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    try insertResourceFixture(database, resourceID: "res_app")
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let url = try #require(URL(string: "https://appstoreconnect.apple.com/apps/123"))
    let event = Event(
        id: "evt_review_rejected",
        provider: "appstoreconnect",
        type: "app.review.rejected",
        resourceID: "res_app",
        resourceName: "Example App",
        severity: .critical,
        title: "App rejected",
        summary: "Example App needs a reviewer reply.",
        timestamp: now,
        actionURL: url,
        fingerprint: "appstoreconnect:app.review.rejected:res_app:REJECTED"
    )
    let item = StatusItem(
        id: "sti_review_rejected",
        resourceID: "res_app",
        severity: .critical,
        title: "App rejected",
        summary: "Example App needs a reviewer reply.",
        state: .open,
        updatedAt: now,
        actionLink: ActionLink(id: "open", label: "Open", url: url)
    )
    let audit = AuditEntry(
        id: "aud_review_rejected",
        title: "Event ingested",
        detail: "app.review.rejected entered the event pipeline.",
        timestamp: now,
        status: "success",
        eventID: event.id
    )

    try store.insertEvent(event)
    try store.insertStatusItem(item)
    try store.insertAuditEntry(audit)
    try database.execute(
        """
        INSERT INTO metrics
        (id, resource_id, label, value, delta, severity, updated_at)
        VALUES ('met_review', 'res_app', 'Review state', 'Rejected', 'now', 'critical', ?)
        """,
        bindings: [.text("2026-07-07T12:00:00Z")]
    )

    let snapshot = try store.dashboardSnapshot(now: now)

    #expect(snapshot.headline == "1 critical item")
    #expect(snapshot.statusItems == [item])
    #expect(snapshot.recentEvents == [event])
    #expect(snapshot.metrics.map(\.label) == ["Review state"])
    #expect(snapshot.integrations.map(\.name) == ["Example Account"])
    #expect(snapshot.auditEntries == [audit])
}

@Test func pluginInstallRecordPersistsPluginVersionAndPermissionDefaults() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let manifest = PluginManifest(
        id: "com.status.github",
        name: "GitHub",
        version: "0.1.0",
        author: "Status Foundry",
        category: "developer",
        description: "Read-only GitHub status events.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .backgroundRefresh],
        domains: ["api.github.com"]
    )
    let verification = PluginPackageVerificationResult(
        pluginID: manifest.id,
        version: manifest.version,
        sha256: "dcd4260b527a28d62ad2a956b00c4f5616416b2fdc0506e6fe5f6b616f5df5aa",
        signedBy: "status-foundry-dev"
    )

    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: "/Application Support/Status/Plugins/com.status.github",
            packagePath: "/Application Support/Status/Packages/com.status.github-0.1.0.statusplugin.zip",
            verification: verification,
            signature: "dev-signature",
            installedAt: now
        )
    )

    #expect(
        try store.installedPlugin(id: manifest.id) == InstalledPlugin(
            id: manifest.id,
            name: manifest.name,
            author: manifest.author,
            description: manifest.description,
            category: manifest.category,
            trustLevel: .official,
            installedVersion: manifest.version,
            installPath: "/Application Support/Status/Plugins/com.status.github",
            installedAt: now,
            updatedAt: now
        )
    )
    #expect(try store.installedPlugins().map(\.id) == [manifest.id])
    #expect(try store.installedPluginVersions(pluginID: manifest.id).first?.manifest == manifest)
    #expect(try store.installedPluginVersions(pluginID: manifest.id).first?.sha256 == verification.sha256)
    #expect(try store.pluginPermissions(pluginID: manifest.id).map(\.permission) == [.backgroundRefresh, .network])
    #expect(try store.pluginPermissions(pluginID: manifest.id).allSatisfy { $0.granted == false })

    let grantedAt = now.addingTimeInterval(60)
    try store.setPluginPermission(pluginID: manifest.id, permission: .network, granted: true, grantedAt: grantedAt)
    #expect(try store.pluginPermissions(pluginID: manifest.id).first(where: { $0.permission == .network })?.granted == true)
    #expect(try store.pluginPermissions(pluginID: manifest.id).first(where: { $0.permission == .network })?.grantedAt == grantedAt)

    try store.setPluginPermission(pluginID: manifest.id, permission: .network, granted: false, grantedAt: nil)
    #expect(try store.pluginPermissions(pluginID: manifest.id).first(where: { $0.permission == .network })?.granted == false)
    #expect(try store.pluginPermissions(pluginID: manifest.id).first(where: { $0.permission == .network })?.grantedAt == nil)
}

@Test func pluginRevocationMarksVersionDisablesPluginAndAudits() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let manifest = PluginManifest(
        id: "com.status.github",
        name: "GitHub",
        version: "0.1.0",
        author: "Status Foundry",
        category: "developer",
        description: "Read-only GitHub status events.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network],
        domains: ["api.github.com"]
    )
    let verification = PluginPackageVerificationResult(
        pluginID: manifest.id,
        version: manifest.version,
        sha256: "dcd4260b527a28d62ad2a956b00c4f5616416b2fdc0506e6fe5f6b616f5df5aa",
        signedBy: "status-foundry-dev"
    )
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: "/Application Support/Status/Plugins/com.status.github",
            packagePath: "/Application Support/Status/Packages/com.status.github-0.1.0.statusplugin.zip",
            verification: verification,
            signature: "signature",
            installedAt: now
        )
    )

    let result = try store.applyPluginRevocations(
        RegistryRevocationsResponse(
            schemaVersion: "1.0.0",
            generatedAt: now,
            revokedPlugins: [],
            revokedVersions: [],
            revokedHashes: [verification.sha256],
            revokedSigningKeys: []
        ),
        checkedAt: now.addingTimeInterval(60)
    )

    #expect(result.disabledPluginIDs == [manifest.id])
    #expect(result.revokedVersions.map(\.id) == ["plv_com_status_github_0_1_0"])
    #expect(try store.installedPlugin(id: manifest.id)?.enabled == false)
    #expect(try store.installedPluginVersions(pluginID: manifest.id).first?.revoked == true)
    #expect(try store.auditEntry(id: "aud_plugin_com_status_github_revoked")?.status == "revoked")
}

@Test func pluginUninstallRemovesActivePluginDataAndKeepsHistory() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let manifest = PluginManifest(
        id: "com.status.github",
        name: "GitHub",
        version: "0.1.0",
        author: "Status Foundry",
        category: "developer",
        description: "Read-only GitHub status events.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .backgroundRefresh],
        domains: ["api.github.com"]
    )
    let packageDefinition = PluginPackageDefinition(
        triggers: [
            PackagedPluginTrigger(
                id: "manual",
                type: .manual,
                label: "Run GitHub check",
                request: "repos"
            )
        ],
        rulePresets: [
            PackagedRulePreset(
                name: "GitHub failures",
                when: PackagedRuleWhen(eventType: "github.workflow.failed", provider: manifest.id),
                conditions: [PackagedRuleCondition(field: "severity", operation: .equals, value: .string("critical"))],
                actions: [PackagedRuleAction(action: "notification", parameters: ["title": "Workflow failed"])]
            )
        ]
    )

    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: "/Application Support/Status/Plugins/com.status.github",
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: "dcd4260b527a28d62ad2a956b00c4f5616416b2fdc0506e6fe5f6b616f5df5aa",
                signedBy: "status-foundry-dev"
            ),
            packageDefinition: packageDefinition,
            installedAt: now
        )
    )
    try store.upsertAccountConfiguration(
        PluginAccountConfiguration(
            id: "acc_github",
            pluginID: manifest.id,
            accountName: "Status",
            variables: ["owner": "statusfoundry"],
            authType: "none"
        ),
        updatedAt: now
    )
    let event = Event(
        id: "evt_history",
        provider: manifest.id,
        type: "github.workflow.failed",
        resourceID: "res_status_repo",
        resourceName: "status",
        severity: .critical,
        title: "Workflow failed",
        summary: "CI failed on main.",
        timestamp: now,
        fingerprint: "github:workflow.failed:res_status_repo:failure"
    )
    let auditEntry = AuditEntry(
        id: "aud_history",
        title: "Plugin ran",
        detail: "GitHub check emitted an event.",
        timestamp: now,
        status: "success",
        eventID: event.id
    )
    try store.insertEvent(event)
    try store.insertAuditEntry(auditEntry)

    #expect(try store.installedPlugin(id: manifest.id) != nil)
    #expect(try store.triggers().map(\.pluginID) == [manifest.id])
    #expect(try store.rules().map(\.provider) == [manifest.id])
    #expect(try store.accountConfigurations(pluginID: manifest.id).map(\.id) == ["acc_github"])

    try store.uninstallPlugin(id: manifest.id)

    #expect(try store.installedPlugin(id: manifest.id) == nil)
    #expect(try store.installedPluginVersions(pluginID: manifest.id).isEmpty)
    #expect(try store.pluginPermissions(pluginID: manifest.id).isEmpty)
    #expect(try store.accountConfigurations(pluginID: manifest.id).isEmpty)
    #expect(try store.triggers().isEmpty)
    #expect(try store.rules().isEmpty)
    #expect(try store.event(id: event.id) == event)
    #expect(try store.auditEntry(id: auditEntry.id) == auditEntry)
}

@Test func genericSyncStatePersistsBootstrapMarkers() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)

    #expect(try store.syncState(ownerType: "app", ownerID: "bundled-plugins") == nil)
    try store.upsertSyncState(ownerType: "app", ownerID: "bundled-plugins", cursor: "installed", updatedAt: now)
    #expect(try store.syncState(ownerType: "app", ownerID: "bundled-plugins") == "installed")
    try store.upsertSyncState(ownerType: "app", ownerID: "bundled-plugins", cursor: "refreshed", updatedAt: now.addingTimeInterval(60))
    #expect(try store.syncState(ownerType: "app", ownerID: "bundled-plugins") == "refreshed")
}

@Test func pluginInstallRejectsVerificationMismatch() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let manifest = PluginManifest(
        id: "com.status.github",
        name: "GitHub",
        version: "0.1.0",
        author: "Status Foundry",
        category: "developer",
        description: "Read-only GitHub status events.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS],
        permissions: [.network],
        domains: ["api.github.com"]
    )

    #expect(throws: PluginInstallationError.verificationPluginMismatch(expected: manifest.id, actual: "com.status.other")) {
        try store.installPlugin(
            PluginInstallRecord(
                manifest: manifest,
                trustLevel: .official,
                installPath: "/Application Support/Status/Plugins/com.status.github",
                verification: PluginPackageVerificationResult(
                    pluginID: "com.status.other",
                    version: manifest.version,
                    sha256: "hash",
                    signedBy: "status-foundry-dev"
                ),
                signature: "dev-signature",
                installedAt: Date(timeIntervalSince1970: 1_783_433_520)
            )
        )
    }
}

@Test func triggerDefinitionRoundTripsThroughSQLite() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let trigger = TriggerDefinition(
        id: "trg_appstore_poll",
        pluginID: "com.status.appstoreconnect",
        accountID: "acc_asc",
        kind: .cron,
        label: "Poll App Store Connect",
        enabled: true,
        intervalSeconds: 900,
        failureCount: 2,
        lastRunAt: now,
        nextRunAt: now.addingTimeInterval(120)
    )

    try store.upsertTrigger(trigger, updatedAt: now)

    #expect(try store.trigger(id: trigger.id) == trigger)
    #expect(try store.triggers() == [trigger])

    try store.setTriggerEnabled(id: trigger.id, enabled: false, updatedAt: now.addingTimeInterval(60))
    #expect(try store.trigger(id: trigger.id)?.enabled == false)
}

@Test func jobRecordRoundTripsThroughSQLite() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let job = JobRecord(
        id: "job_poll_01",
        pluginID: "com.status.github",
        triggerID: "trg_github",
        accountID: "acc_github",
        status: .success,
        queuedAt: now,
        startedAt: now.addingTimeInterval(1),
        finishedAt: now.addingTimeInterval(3),
        emittedEventIDs: ["evt_01", "evt_02"]
    )

    try store.upsertJob(job)

    #expect(try store.job(id: job.id) == job)
}

@Test func nextQueuedJobReadsOldestQueuedSQLiteJob() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let first = JobRecord(
        id: "job_01",
        pluginID: "com.status.github",
        triggerID: "trg_github",
        status: .queued,
        queuedAt: now
    )
    let second = JobRecord(
        id: "job_02",
        pluginID: "com.status.github",
        triggerID: "trg_github",
        status: .queued,
        queuedAt: now.addingTimeInterval(60)
    )
    let failed = JobRecord(
        id: "job_00_failed",
        pluginID: "com.status.github",
        triggerID: "trg_github",
        status: .failed,
        queuedAt: now.addingTimeInterval(-60),
        finishedAt: now,
        error: "Unauthorized"
    )

    try store.upsertJob(second)
    try store.upsertJob(failed)
    try store.upsertJob(first)

    #expect(try store.nextQueuedJob() == first)
}

private func temporaryDatabase() throws -> SQLiteDatabase {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-\(UUID().uuidString).sqlite")
        .path
    return try SQLiteDatabase(path: path)
}

private func insertPluginFixture(_ database: SQLiteDatabase, pluginID: String) throws {
    let now = "2026-07-07T12:00:00Z"
    try database.execute(
        """
        INSERT INTO plugins
        (id, name, author, description, category, trust_level, installed_version, install_path, installed_at, updated_at)
        VALUES (?, ?, 'Status Foundry', 'Fixture plugin', 'monitoring', 'official', '0.1.0', '/tmp/plugin', ?, ?)
        """,
        bindings: [.text(pluginID), .text(pluginID), .text(now), .text(now)]
    )
}

private func insertResourceFixture(_ database: SQLiteDatabase, resourceID: String) throws {
    let now = "2026-07-07T12:00:00Z"
    try database.execute(
        """
        INSERT INTO plugins
        (id, name, author, description, category, trust_level, installed_version, install_path, installed_at, updated_at)
        VALUES (?, 'App Store Connect', 'Status Foundry', 'Fixture plugin', 'developer', 'official', '0.1.0', '/tmp/plugin', ?, ?)
        """,
        bindings: [.text("com.status.appstoreconnect"), .text(now), .text(now)]
    )
    try database.execute(
        """
        INSERT INTO accounts
        (id, plugin_id, provider, display_name, auth_type, created_at, updated_at)
        VALUES (?, 'com.status.appstoreconnect', 'appstoreconnect', 'Example Account', 'none', ?, ?)
        """,
        bindings: [.text("acc_fixture"), .text(now), .text(now)]
    )
    try database.execute(
        """
        INSERT INTO resources
        (id, account_id, plugin_id, type, external_id, name, first_seen_at, last_seen_at)
        VALUES (?, 'acc_fixture', 'com.status.appstoreconnect', 'app', '123', 'Example App', ?, ?)
        """,
        bindings: [.text(resourceID), .text(now), .text(now)]
    )
    try database.execute(
        """
        INSERT INTO jobs
        (id, plugin_id, trigger_id, account_id, status, started_at)
        VALUES ('job_01poll', 'com.status.appstoreconnect', 'trg_fixture', 'acc_fixture', 'succeeded', ?)
        """,
        bindings: [.text(now)]
    )
}

private extension Dictionary where Key == String, Value == SQLiteValue {
    func requiredText(_ column: String) throws -> String {
        guard case .text(let value)? = self[column] else {
            throw PersistenceError.missingColumn(column)
        }
        return value
    }
}
