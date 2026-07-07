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
        status: "success"
    )

    try store.insertEvent(event)
    try store.insertStatusItem(statusItem)
    try store.insertAuditEntry(auditEntry)

    #expect(try store.event(id: event.id) == event)
    #expect(try store.statusItem(id: statusItem.id)?.title == statusItem.title)
    #expect(try store.statusItem(id: statusItem.id)?.actionLink?.url == url)
    #expect(try store.auditEntry(id: auditEntry.id) == auditEntry)
}

private func temporaryDatabase() throws -> SQLiteDatabase {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-\(UUID().uuidString).sqlite")
        .path
    return try SQLiteDatabase(path: path)
}

private extension Dictionary where Key == String, Value == SQLiteValue {
    func requiredText(_ column: String) throws -> String {
        guard case .text(let value)? = self[column] else {
            throw PersistenceError.missingColumn(column)
        }
        return value
    }
}
