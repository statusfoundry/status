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
