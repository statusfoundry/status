import Foundation

public enum LocalStatusStore {
    public static func applicationSupportDatabaseURL(
        appName: String = "Status",
        fileManager: FileManager = .default
    ) throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent(appName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("status.sqlite")
    }

    public static func open(databaseURL: URL) throws -> StatusPersistenceStore {
        let database = try SQLiteDatabase(path: databaseURL.path)
        try StatusDatabaseMigrator.migrate(database)
        return StatusPersistenceStore(database: database)
    }

    public static func openApplicationSupportStore() throws -> StatusPersistenceStore {
        try open(databaseURL: applicationSupportDatabaseURL())
    }
}
