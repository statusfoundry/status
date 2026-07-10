import Foundation
import CryptoKit
import Testing
@testable import StatusCore

@Test func pluginRuntimeServiceRunsInstalledWebsitePluginRequest() async throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-runtime-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: [
        ("requests.json", Data("""
        {
          "requests": {
            "check_site": {
              "method": "GET",
              "url": "https://{{host}}",
              "timeoutSeconds": 15
            }
          }
        }
        """.utf8)),
        ("mappings.json", Data("""
        {
          "resources": [
            {
              "type": "website",
              "request": "check_site",
              "id": "{{host}}",
              "name": "{{host}}",
              "actionUrl": "https://{{host}}"
            }
          ],
          "events": [
            {
              "type": "website.down",
              "request": "check_site",
              "when": "$.statusCode >= 500 || $.reachable == false",
              "resourceId": "{{host}}",
              "title": "Website down",
              "summary": "{{host}} is not responding normally.",
              "severity": "critical",
              "actionUrl": "https://{{host}}"
            }
          ]
        }
        """.utf8))
    ])
    try packageData.write(to: packageURL)
    let manifest = PluginManifest(
        id: "com.status.website",
        name: "Website Uptime",
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "ops",
        description: "Check configured websites.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .userConfiguredDomains, .backgroundRefresh],
        domains: []
    )
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: try PluginPackageDefinition.decode(from: packageData),
            installedAt: now
        )
    )
    try grantRuntimePermissions(manifest.permissions, pluginID: manifest.id, store: store, at: now)
    try store.upsertRule(
        Rule(
            id: "rul_notify_website_down",
            name: "Notify website down",
            enabled: true,
            provider: manifest.id,
            eventType: "website.down",
            conditions: [],
            actions: [
                RuleActionDefinition(action: "notification.show", parameters: ["title": "Website needs attention"])
            ]
        ),
        updatedAt: now
    )
    let url = try #require(URL(string: "https://status-registry.hakobs.com"))
    let dispatcher = RecordingActionEffectDispatcher()
    let service = PluginRuntimeService(
        store: store,
        transport: RuntimeFakeTransport(responses: [
            url: PluginHTTPResponse(data: Data("Unavailable".utf8), statusCode: 503, url: url)
        ]),
        actionRunner: ActionRunner(now: { now }),
        effectDispatcher: dispatcher
    )

    let result = try await service.runInstalledPluginRequest(
        PluginRuntimeRequest(
            pluginID: manifest.id,
            requestID: "check_site",
            accountID: "acct_status_registry",
            accountName: "Status registry",
            variables: ["host": "status-registry.hakobs.com"],
            now: now
        )
    )

    let jobID = "job_com_status_website_check_site_acct_status_registry_1783433520"
    #expect(result.mappingOutput.resources.map(\.resource.id) == ["acct_status_registry:status-registry.hakobs.com"])
    #expect(result.mappingOutput.events.map(\.type) == ["website.down"])
    #expect(try store.account(id: "acct_status_registry")?.displayName == "Status registry")
    #expect(try store.job(id: jobID)?.status == .success)
    #expect(try store.resource(id: "acct_status_registry:status-registry.hakobs.com")?.name == "status-registry.hakobs.com")
    #expect(try store.statusItemCount() == 1)
    #expect(try store.auditEntry(id: "aud_\(jobID)_success")?.status == "success")
    let eventID = result.mappingOutput.events[0].id
    let actionRunID = "run_rul_notify_website_down_\(eventID)_0"
    #expect(try store.actionRun(id: actionRunID)?.status == .success)
    #expect(dispatcher.dispatchedEffects.flatMap(\.notifications) == [
        ActionRuntimeNotification(
            title: "Website needs attention",
            body: "status-registry.hakobs.com is not responding normally.",
            eventID: eventID,
            actionRunID: actionRunID
        )
    ])
    #expect(try store.notification(id: "ntf_\(actionRunID)")?.deliveredAt != nil)
}

@Test func pluginRuntimeServicePreviewsConfiguredRequestWithoutPersistingJobOutput() async throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-preview-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: [
        ("requests.json", Data("""
        {
          "requests": {
            "check_site": {
              "method": "GET",
              "url": "https://{{host}}",
              "timeoutSeconds": 15
            }
          }
        }
        """.utf8)),
        ("mappings.json", Data("""
        {
          "resources": [
            {
              "type": "website",
              "request": "check_site",
              "id": "{{host}}",
              "name": "{{host}}"
            }
          ],
          "events": []
        }
        """.utf8))
    ])
    try packageData.write(to: packageURL)
    let manifest = PluginManifest(
        id: "com.status.website.preview",
        name: "Website Preview",
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "ops",
        description: "Preview configured website requests.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network],
        domains: ["example.com"]
    )
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: try PluginPackageDefinition.decode(from: packageData),
            installedAt: now
        )
    )
    try grantRuntimePermissions(manifest.permissions, pluginID: manifest.id, store: store, at: now)
    try store.upsertAccountConfiguration(
        PluginAccountConfiguration(
            id: "acct_preview",
            pluginID: manifest.id,
            accountName: "Preview",
            variables: ["host": "example.com"]
        ),
        updatedAt: now
    )
    let url = try #require(URL(string: "https://example.com"))
    let service = PluginRuntimeService(
        store: store,
        transport: RuntimeFakeTransport(responses: [
            url: PluginHTTPResponse(data: Data(#"{"ok":true}"#.utf8), statusCode: 200, url: url)
        ])
    )

    let result = try await service.previewConfiguredPluginRequest(
        pluginID: manifest.id,
        requestID: "check_site",
        accountID: "acct_preview",
        now: now
    )

    #expect(result.pluginID == manifest.id)
    #expect(result.requestID == "check_site")
    #expect(result.accountID == "acct_preview")
    #expect(result.method == "GET")
    #expect(result.url == url)
    #expect(result.statusCode == 200)
    #expect(result.responseByteCount == 11)
    #expect(result.bodyPreview == #"{"ok":true}"#)
    #expect(try store.recentJobs(pluginID: manifest.id).isEmpty)
    #expect(try store.resources(pluginID: manifest.id).isEmpty)
}

@Test func pluginRuntimeServiceRequiresGrantedNetworkPermission() async throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-runtime-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: [
        ("requests.json", Data("""
        {
          "requests": {
            "check_site": {
              "method": "GET",
              "url": "https://example.com"
            }
          }
        }
        """.utf8)),
        ("mappings.json", Data("""
        {
          "resources": [],
          "events": []
        }
        """.utf8))
    ])
    try packageData.write(to: packageURL)
    let manifest = PluginManifest(
        id: "com.status.website",
        name: "Website Uptime",
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "ops",
        description: "Check websites.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network],
        domains: ["example.com"]
    )
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: try PluginPackageDefinition.decode(from: packageData),
            installedAt: now
        )
    )
    let service = PluginRuntimeService(store: store)

    await #expect(throws: PluginRuntimeServiceError.missingPermission(pluginID: manifest.id, permission: .network)) {
        _ = try await service.runInstalledPluginRequest(
            PluginRuntimeRequest(
                pluginID: manifest.id,
                requestID: "check_site",
                accountID: "acct_example",
                accountName: "Example",
                now: now
            )
        )
    }
}

@Test func pluginRuntimeServiceRunsNextQueuedConfiguredWebsiteJob() async throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-runtime-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: [
        ("requests.json", Data("""
        {
          "requests": {
            "check_site": {
              "method": "GET",
              "url": "https://{{host}}",
              "timeoutSeconds": 15
            }
          }
        }
        """.utf8)),
        ("mappings.json", Data("""
        {
          "resources": [
            {
              "type": "website",
              "request": "check_site",
              "id": "{{host}}",
              "name": "{{host}}",
              "actionUrl": "https://{{host}}"
            }
          ],
          "events": []
        }
        """.utf8))
    ])
    try packageData.write(to: packageURL)
    let manifest = PluginManifest(
        id: WebsitePluginSetup.pluginID,
        name: "Website Uptime",
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "ops",
        description: "Check configured websites.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .userConfiguredDomains, .backgroundRefresh],
        domains: []
    )
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: try PluginPackageDefinition.decode(from: packageData),
            installedAt: now
        )
    )
    try grantRuntimePermissions(manifest.permissions, pluginID: manifest.id, store: store, at: now)
    try store.upsertTrigger(
        TriggerDefinition(
            id: "trg_com_status_website_refresh_site",
            pluginID: WebsitePluginSetup.pluginID,
            kind: .manual,
            label: "Refresh website status",
            requestID: WebsitePluginSetup.requestID
        ),
        updatedAt: now
    )
    let url = try #require(URL(string: "https://status-registry.hakobs.com"))
    let service = PluginRuntimeService(
        store: store,
        transport: RuntimeFakeTransport(responses: [
            url: PluginHTTPResponse(data: Data("OK".utf8), statusCode: 200, url: url)
        ])
    )
    try service.saveAccountConfiguration(
        PluginAccountConfiguration(
            id: "acct_website_status_registry",
            pluginID: WebsitePluginSetup.pluginID,
            accountName: "status-registry.hakobs.com",
            variables: ["host": "status-registry.hakobs.com"]
        ),
        now: now
    )

    let queued = try service.enqueueManualConfiguredPluginRun(
        pluginID: WebsitePluginSetup.pluginID,
        accountID: "acct_website_status_registry",
        now: now
    )
    let result = try await service.runNextQueuedPluginJob(now: now.addingTimeInterval(1))

    #expect(queued.status == .queued)
    #expect(result?.mappingOutput.resources.map(\.resource.id) == ["acct_website_status_registry:status-registry.hakobs.com"])
    #expect(try store.job(id: queued.id)?.status == .success)
    #expect(try store.job(id: queued.id)?.triggerID == "trg_com_status_website_refresh_site")
    #expect(try store.auditEntry(id: "aud_\(queued.id)_success")?.status == "success")
}

@Test func pluginRuntimeServiceRunsDueConfiguredCronWebsiteJob() async throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-runtime-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: [
        ("requests.json", Data("""
        {
          "requests": {
            "check_site": {
              "method": "GET",
              "url": "https://{{host}}",
              "timeoutSeconds": 15
            }
          }
        }
        """.utf8)),
        ("mappings.json", Data("""
        {
          "resources": [
            {
              "type": "website",
              "request": "check_site",
              "id": "{{host}}",
              "name": "{{host}}",
              "actionUrl": "https://{{host}}"
            }
          ],
          "events": []
        }
        """.utf8))
    ])
    try packageData.write(to: packageURL)
    let manifest = PluginManifest(
        id: WebsitePluginSetup.pluginID,
        name: "Website Uptime",
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "ops",
        description: "Check configured websites.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .userConfiguredDomains, .backgroundRefresh],
        domains: []
    )
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: try PluginPackageDefinition.decode(from: packageData),
            installedAt: now
        )
    )
    try grantRuntimePermissions(manifest.permissions, pluginID: manifest.id, store: store, at: now)
    try store.upsertTrigger(
        TriggerDefinition(
            id: "trg_com_status_website_poll_site",
            pluginID: WebsitePluginSetup.pluginID,
            kind: .cron,
            label: "Check website uptime",
            intervalSeconds: 300,
            requestID: WebsitePluginSetup.requestID
        ),
        updatedAt: now
    )
    let url = try #require(URL(string: "https://status-registry.hakobs.com"))
    let service = PluginRuntimeService(
        store: store,
        transport: RuntimeFakeTransport(responses: [
            url: PluginHTTPResponse(data: Data("OK".utf8), statusCode: 200, url: url)
        ])
    )
    try service.saveAccountConfiguration(
        PluginAccountConfiguration(
            id: "acct_website_status_registry",
            pluginID: WebsitePluginSetup.pluginID,
            accountName: "status-registry.hakobs.com",
            variables: ["host": "status-registry.hakobs.com"]
        ),
        now: now
    )

    let results = try await service.runDueConfiguredPluginJobs(now: now)

    let jobID = "job_com_status_website_check_site_acct_website_status_registry_1783433520"
    #expect(results.map(\.mappingOutput.resources).flatMap { $0 }.map(\.resource.id) == ["acct_website_status_registry:status-registry.hakobs.com"])
    #expect(try store.job(id: jobID)?.status == .success)
    #expect(try store.job(id: jobID)?.triggerID == "trg_com_status_website_poll_site")
    #expect(try store.trigger(id: "trg_com_status_website_poll_site")?.lastRunAt == now)
    #expect(try store.trigger(id: "trg_com_status_website_poll_site")?.nextRunAt == now.addingTimeInterval(300))
    #expect(try store.auditEntry(id: "aud_\(jobID)_success")?.status == "success")
    #expect(try service.enqueueDueConfiguredPluginJobs(now: now.addingTimeInterval(60)).isEmpty)
}

@Test func pluginRuntimeServiceRunsDueCronForEveryConfiguredAccount() async throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-runtime-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: [
        ("requests.json", Data("""
        {
          "requests": {
            "check_site": {
              "method": "GET",
              "url": "https://{{host}}",
              "timeoutSeconds": 15
            }
          }
        }
        """.utf8)),
        ("mappings.json", Data("""
        {
          "resources": [
            {
              "type": "website",
              "request": "check_site",
              "id": "{{host}}",
              "name": "{{host}}",
              "actionUrl": "https://{{host}}"
            }
          ],
          "events": []
        }
        """.utf8))
    ])
    try packageData.write(to: packageURL)
    let manifest = PluginManifest(
        id: WebsitePluginSetup.pluginID,
        name: "Website Uptime",
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "ops",
        description: "Check configured websites.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .userConfiguredDomains, .backgroundRefresh],
        domains: []
    )
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: try PluginPackageDefinition.decode(from: packageData),
            installedAt: now
        )
    )
    try grantRuntimePermissions(manifest.permissions, pluginID: manifest.id, store: store, at: now)
    try store.upsertTrigger(
        TriggerDefinition(
            id: "trg_com_status_website_poll_sites",
            pluginID: WebsitePluginSetup.pluginID,
            kind: .cron,
            label: "Check website uptime",
            intervalSeconds: 300,
            requestID: WebsitePluginSetup.requestID
        ),
        updatedAt: now
    )
    try store.upsertAccountConfiguration(
        PluginAccountConfiguration(
            id: "acct_website_status_registry",
            pluginID: WebsitePluginSetup.pluginID,
            accountName: "status-registry.hakobs.com",
            variables: ["host": "status-registry.hakobs.com"]
        ),
        updatedAt: now
    )
    try store.upsertAccountConfiguration(
        PluginAccountConfiguration(
            id: "acct_website_status_site",
            pluginID: WebsitePluginSetup.pluginID,
            accountName: "status.hakobs.com",
            variables: ["host": "status.hakobs.com"]
        ),
        updatedAt: now
    )
    let registryURL = try #require(URL(string: "https://status-registry.hakobs.com"))
    let siteURL = try #require(URL(string: "https://status.hakobs.com"))
    let service = PluginRuntimeService(
        store: store,
        transport: RuntimeFakeTransport(responses: [
            registryURL: PluginHTTPResponse(data: Data("OK".utf8), statusCode: 200, url: registryURL),
            siteURL: PluginHTTPResponse(data: Data("OK".utf8), statusCode: 200, url: siteURL)
        ])
    )

    let results = try await service.runDueConfiguredPluginJobs(now: now)

    let resourceIDs = results.flatMap(\.mappingOutput.resources).map(\.resource.id).sorted()
    #expect(resourceIDs == [
        "acct_website_status_registry:status-registry.hakobs.com",
        "acct_website_status_site:status.hakobs.com"
    ])
    #expect(try store.job(id: "job_com_status_website_check_site_acct_website_status_registry_1783433520")?.status == .success)
    #expect(try store.job(id: "job_com_status_website_check_site_acct_website_status_site_1783433520")?.status == .success)
    #expect(try store.trigger(id: "trg_com_status_website_poll_sites")?.nextRunAt == now.addingTimeInterval(300))
}

@Test func pluginRuntimeServiceBacksOffFailedCronJobAndSkipsUntilRetryWindow() async throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-runtime-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: [
        ("requests.json", Data("""
        {
          "requests": {
            "check_site": {
              "method": "GET",
              "url": "https://{{host}}",
              "timeoutSeconds": 15
            }
          }
        }
        """.utf8)),
        ("mappings.json", Data("""
        {
          "resources": [],
          "events": []
        }
        """.utf8))
    ])
    try packageData.write(to: packageURL)
    let manifest = PluginManifest(
        id: WebsitePluginSetup.pluginID,
        name: "Website Uptime",
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "ops",
        description: "Check configured websites.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .userConfiguredDomains, .backgroundRefresh],
        domains: []
    )
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: try PluginPackageDefinition.decode(from: packageData),
            installedAt: now
        )
    )
    try grantRuntimePermissions(manifest.permissions, pluginID: manifest.id, store: store, at: now)
    try store.upsertTrigger(
        TriggerDefinition(
            id: "trg_com_status_website_poll_site",
            pluginID: WebsitePluginSetup.pluginID,
            kind: .cron,
            label: "Check website uptime",
            intervalSeconds: 300,
            requestID: WebsitePluginSetup.requestID
        ),
        updatedAt: now
    )
    try store.upsertAccountConfiguration(
        PluginAccountConfiguration(
            id: "acct_website_status_registry",
            pluginID: WebsitePluginSetup.pluginID,
            accountName: "status-registry.hakobs.com",
            variables: ["host": "status-registry.hakobs.com"]
        ),
        updatedAt: now
    )
    let service = PluginRuntimeService(
        store: store,
        transport: RuntimeFailingTransport(),
        baseBackoffSeconds: 60,
        maxBackoffSeconds: 600
    )

    await #expect(throws: (any Error).self) {
        _ = try await service.runDueConfiguredPluginJobs(now: now)
    }

    let trigger = try #require(try store.trigger(id: "trg_com_status_website_poll_site"))
    let jobID = "job_com_status_website_check_site_acct_website_status_registry_1783433520"
    #expect(trigger.failureCount == 1)
    #expect(trigger.nextRunAt == now.addingTimeInterval(60))
    #expect(try store.job(id: jobID)?.status == .failed)
    #expect(try store.auditEntry(id: "aud_\(jobID)_failed")?.status == "failed")
    #expect(try service.enqueueDueConfiguredPluginJobs(now: now.addingTimeInterval(30)).isEmpty)
}

@Test func pluginRuntimeServiceAuditsSkippedCronTriggerWithoutBackgroundPermission() throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-runtime-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: [
        ("requests.json", Data("""
        {
          "requests": {
            "check_site": {
              "method": "GET",
              "url": "https://{{host}}",
              "timeoutSeconds": 15
            }
          }
        }
        """.utf8)),
        ("mappings.json", Data("""
        {
          "resources": [],
          "events": []
        }
        """.utf8))
    ])
    try packageData.write(to: packageURL)
    let manifest = PluginManifest(
        id: WebsitePluginSetup.pluginID,
        name: "Website Uptime",
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "ops",
        description: "Check configured websites.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .userConfiguredDomains, .backgroundRefresh],
        domains: []
    )
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: try PluginPackageDefinition.decode(from: packageData),
            installedAt: now
        )
    )
    try grantRuntimePermissions([.network, .userConfiguredDomains], pluginID: manifest.id, store: store, at: now)
    try store.upsertTrigger(
        TriggerDefinition(
            id: "trg_com_status_website_poll_site",
            pluginID: WebsitePluginSetup.pluginID,
            kind: .cron,
            label: "Check website uptime",
            intervalSeconds: 300,
            requestID: WebsitePluginSetup.requestID
        ),
        updatedAt: now
    )
    try store.upsertAccountConfiguration(
        PluginAccountConfiguration(
            id: "acct_website_status_registry",
            pluginID: WebsitePluginSetup.pluginID,
            accountName: "status-registry.hakobs.com",
            variables: ["host": "status-registry.hakobs.com"]
        ),
        updatedAt: now
    )
    let service = PluginRuntimeService(store: store)

    let jobs = try service.enqueueDueConfiguredPluginJobs(now: now)

    let audit = try #require(try store.auditEntry(
        id: "aud_trg_com_status_website_poll_site_skipped_background_refresh_permission"
    ))
    #expect(jobs.isEmpty)
    #expect(audit.status == "skipped")
    #expect(audit.title == "Plugin trigger skipped")
    #expect(audit.detail == "Status skipped Check website uptime because com.status.website does not have background refresh permission.")
    #expect(try store.trigger(id: "trg_com_status_website_poll_site")?.nextRunAt == nil)
}

@Test func pluginPackageDefinitionDecodesSetupSchema() throws {
    let packageData = runtimeStoredZip(files: [
        ("setup.schema.json", Data("""
        {
          "title": "Website to check",
          "description": "Configure one host.",
          "fields": [
            {
              "key": "host",
              "label": "Host",
              "type": "hostname",
              "placeholder": "status-registry.hakobs.com",
              "help": "Enter a host name.",
              "required": true
            }
          ]
        }
        """.utf8))
    ])

    let definition = try PluginPackageDefinition.decode(from: packageData)

    #expect(definition.setup?.title == "Website to check")
    #expect(definition.setup?.fields == [
        PackagedPluginSetupField(
            id: "host",
            label: "Host",
            type: .hostname,
            placeholder: "status-registry.hakobs.com",
            help: "Enter a host name.",
            required: true
        )
    ])
}

@Test func pluginPackageDefinitionDecodesCanonicalSetupFields() throws {
    let packageData = runtimeStoredZip(files: [
        ("auth.json", Data("""
        {
          "type": "bearer-token",
          "fields": [
            {
              "key": "token",
              "label": "Personal access token",
              "type": "secret",
              "required": true
            }
          ]
        }
        """.utf8)),
        ("setup.schema.json", Data("""
        {
          "title": "Repository",
          "fields": [
            {
              "key": "owner",
              "label": "Owner",
              "type": "text",
              "required": true,
              "default": "statusfoundry"
            },
            {
              "key": "visibility",
              "label": "Visibility",
              "type": "select",
              "required": true,
              "default": "public",
              "options": [
                { "value": "public", "label": "Public" },
                { "value": "private", "label": "Private" }
              ]
            }
          ]
        }
        """.utf8))
    ])

    let definition = try PluginPackageDefinition.decode(from: packageData)

    #expect(definition.auth == PackagedPluginAuth(
        type: .bearerToken,
        fields: [
            PackagedPluginSetupField(
                id: "token",
                label: "Personal access token",
                type: .secret,
                required: true
            )
        ]
    ))
    #expect(definition.setup?.fields == [
        PackagedPluginSetupField(
            id: "owner",
            label: "Owner",
            type: .text,
            required: true,
            defaultValue: "statusfoundry"
        ),
        PackagedPluginSetupField(
            id: "visibility",
            label: "Visibility",
            type: .select,
            required: true,
            defaultValue: "public",
            options: [
                PackagedPluginSetupFieldOption(value: "public", label: "Public"),
                PackagedPluginSetupFieldOption(value: "private", label: "Private")
            ]
        )
    ])
}

@Test func pluginPackageDefinitionDecodesActions() throws {
    let packageData = runtimeStoredZip(files: [
        ("requests.json", Data("""
        {
          "requests": {
            "create_issue": {
              "method": "POST",
              "url": "https://example.atlassian.net/rest/api/3/issue"
            }
          }
        }
        """.utf8)),
        ("actions.json", Data("""
        {
          "actions": [
            {
              "id": "jira.createIssue",
              "label": "Create Jira issue",
              "description": "Creates an issue in the configured Jira project.",
              "requiresWritePermission": true,
              "safety": "review-required",
              "inputSchema": {
                "fields": [
                  {
                    "key": "project",
                    "label": "Project",
                    "type": "select",
                    "required": true,
                    "options": [
                      { "value": "STATUS", "label": "STATUS" }
                    ]
                  },
                  {
                    "key": "summary",
                    "label": "Summary",
                    "type": "template",
                    "required": true,
                    "default": "{{event.title}}"
                  }
                ]
              },
              "request": "create_issue"
            }
          ]
        }
        """.utf8))
    ])

    let definition = try PluginPackageDefinition.decode(from: packageData)

    #expect(definition.actions == [
        PackagedPluginAction(
            id: "jira.createIssue",
            label: "Create Jira issue",
            description: "Creates an issue in the configured Jira project.",
            requiresWritePermission: true,
            safety: .reviewRequired,
            inputSchema: PackagedPluginActionInputSchema(fields: [
                PackagedPluginActionInputField(
                    key: "project",
                    label: "Project",
                    type: .select,
                    required: true,
                    options: [PackagedPluginSetupFieldOption(value: "STATUS", label: "STATUS")]
                ),
                PackagedPluginActionInputField(
                    key: "summary",
                    label: "Summary",
                    type: .template,
                    required: true,
                    defaultValue: "{{event.title}}"
                )
            ]),
            request: "create_issue"
        )
    ])
}

@Test func pluginPackageDefinitionDecodesViews() throws {
    let packageData = runtimeStoredZip(files: [
        ("views.json", Data("""
        {
          "dashboardTile": {
            "primaryFields": ["name"],
            "secondaryFields": ["visibility", "actionUrl"]
          },
          "views": [
            {
              "id": "repositories",
              "type": "resource_list",
              "title": "Repositories",
              "resourceType": "repository",
              "fields": ["name", "visibility"]
            },
            {
              "id": "timeline",
              "type": "timeline",
              "title": "Recent Activity",
              "resourceType": "repository"
            }
          ]
        }
        """.utf8))
    ])

    let definition = try PluginPackageDefinition.decode(from: packageData)

    #expect(definition.views == [
        PackagedPluginView(
            id: "repositories",
            type: .resourceList,
            title: "Repositories",
            resourceType: "repository",
            fields: ["name", "visibility"]
        ),
        PackagedPluginView(
            id: "timeline",
            type: .timeline,
            title: "Recent Activity",
            resourceType: "repository"
        )
    ])
    #expect(definition.dashboardTile == PackagedPluginDashboardTile(
        primaryFields: ["name"],
        secondaryFields: ["visibility", "actionUrl"]
    ))
}

@Test func pluginPackageDefinitionDecodesIconAsset() throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
      <rect width="16" height="16" rx="3" fill="#111111"/>
    </svg>
    """
    let packageData = runtimeStoredZip(files: [
        ("README.md", Data("# Example\n".utf8)),
        ("icon.svg", Data(svg.utf8))
    ])

    let definition = try PluginPackageDefinition.decode(from: packageData)

    #expect(definition.readmeMarkdown == "# Example\n")
    #expect(definition.iconAsset == PackagedPluginIconAsset(path: "icon.svg", svgText: svg))
}

@Test func pluginPackageDefinitionRejectsActiveIconAsset() throws {
    let packageData = runtimeStoredZip(files: [
        ("icon.svg", Data(#"<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"></svg>"#.utf8))
    ])

    #expect(throws: PluginPackageDefinitionError.invalidIconAsset("icon.svg")) {
        _ = try PluginPackageDefinition.decode(from: packageData)
    }
}

@Test func pluginPackageDefinitionRejectsRemoteReferencedIconAsset() throws {
    let packageData = runtimeStoredZip(files: [
        ("icon.svg", Data(#"<svg xmlns="http://www.w3.org/2000/svg"><use href="https://example.com/icon.svg#mark"/></svg>"#.utf8))
    ])

    #expect(throws: PluginPackageDefinitionError.invalidIconAsset("icon.svg")) {
        _ = try PluginPackageDefinition.decode(from: packageData)
    }
}

@Test func pluginPackageDefinitionRejectsActionWithMissingRequest() throws {
    let packageData = runtimeStoredZip(files: [
        ("actions.json", Data("""
        {
          "actions": [
            {
              "id": "jira.createIssue",
              "label": "Create Jira issue",
              "requiresWritePermission": true,
              "request": "create_issue"
            }
          ]
        }
        """.utf8))
    ])

    #expect(throws: PluginPackageDefinitionError.missingActionRequest(actionID: "jira.createIssue", requestID: "create_issue")) {
        _ = try PluginPackageDefinition.decode(from: packageData)
    }
}

@Test func genericPluginSetupStoresBearerTokenInCredentialStore() throws {
    let database = try temporaryRuntimeDatabase()
    try insertRuntimePluginFixture(database, pluginID: "com.status.github")
    let store = StatusPersistenceStore(database: database)
    let service = PluginRuntimeService(store: store, credentialStore: nil)
    let credentials = InMemoryCredentialStore()
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let plugin = InstalledPlugin(
        id: "com.status.github",
        name: "GitHub",
        author: "Status Foundry",
        description: "Read-only repository checks.",
        category: "developer",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/plugin",
        auth: PackagedPluginAuth(
            type: .bearerToken,
            fields: [
                PackagedPluginSetupField(
                    id: "token",
                    label: "Personal access token",
                    type: .secret,
                    required: true
                )
            ]
        ),
        setup: PackagedPluginSetup(
            title: "Repository",
            fields: [
                PackagedPluginSetupField(id: "owner", label: "Owner", type: .text, required: true),
                PackagedPluginSetupField(id: "repo", label: "Repository", type: .text, required: true)
            ]
        ),
        installedAt: now,
        updatedAt: now
    )

    let message = try PluginSetupConfiguration.saveValues(
        ["token": "github_pat_example", "owner": "statusfoundry", "repo": "status"],
        for: plugin,
        service: service,
        credentialStore: credentials,
        now: now
    )

    let configuration = try #require(store.accountConfigurations(pluginID: "com.status.github").first)
    let credentialRef = try #require(configuration.credentialRef)
    #expect(message == "Saved statusfoundry/status.")
    #expect(configuration.authType == "bearer-token")
    #expect(configuration.variables == ["owner": "statusfoundry", "repo": "status"])
    #expect(try credentials.read(reference: credentialRef) == Data("github_pat_example".utf8))
}

@Test func pluginSetupSeedsDashboardTileDefaultsForNewApps() throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let service = PluginRuntimeService(store: store, credentialStore: nil)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let manifest = PluginManifest(
        id: "com.status.website",
        name: "Website",
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "operations",
        description: "Website checks.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network],
        domains: ["example.com"]
    )
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: "/tmp/plugin",
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: "website123",
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            installedAt: now
        )
    )
    let plugin = InstalledPlugin(
        id: "com.status.website",
        name: "Website",
        author: "Status Foundry",
        description: "Website checks.",
        category: "operations",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/plugin",
        setup: PackagedPluginSetup(
            title: "Website",
            fields: [
                PackagedPluginSetupField(id: "host", label: "Host", type: .hostname, required: true)
            ]
        ),
        dashboardTile: PackagedPluginDashboardTile(
            primaryFields: ["reachable"],
            secondaryFields: ["statusCode", "responseTimeMs", "actionUrl"]
        ),
        installedAt: now,
        updatedAt: now
    )

    _ = try PluginSetupConfiguration.saveValues(
        ["host": "https://example.com"],
        for: plugin,
        service: service,
        now: now
    )

    let configuration = try #require(store.accountConfigurations(pluginID: "com.status.website").first)
    #expect(configuration.variables[PluginSetupConfiguration.dashboardTileFieldsKey] == "reachable,statusCode,responseTimeMs,actionUrl")
}

@Test func oauthSetupValidatesRequiredFieldsBeforeStoringCredential() throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let service = PluginRuntimeService(store: store, credentialStore: nil)
    let credentials = RecordingCredentialStore()
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let plugin = InstalledPlugin(
        id: "com.status.oauthgithub",
        name: "OAuth GitHub",
        author: "Status Foundry",
        description: "OAuth-backed repository checks.",
        category: "developer",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/plugin",
        auth: PackagedPluginAuth(type: .oauth2),
        setup: PackagedPluginSetup(
            title: "Repository",
            fields: [
                PackagedPluginSetupField(id: "owner", label: "Owner", type: .text, required: true)
            ]
        ),
        installedAt: now,
        updatedAt: now
    )

    #expect(throws: PluginSetupConfigurationError.missingRequiredField("Owner")) {
        try PluginSetupConfiguration.saveOAuthTokenSet(
            PluginOAuthTokenSet(accessToken: "oauth_access", refreshToken: "oauth_refresh"),
            setupValues: [:],
            for: plugin,
            service: service,
            credentialStore: credentials,
            now: now
        )
    }
    #expect(credentials.storedReferences.isEmpty)
}

@Test func genericPluginSetupUpdatesSpecificConfiguredAccount() throws {
    let database = try temporaryRuntimeDatabase()
    try insertRuntimePluginFixture(database, pluginID: "com.status.github")
    let store = StatusPersistenceStore(database: database)
    let service = PluginRuntimeService(store: store, credentialStore: nil)
    let credentials = InMemoryCredentialStore()
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let plugin = InstalledPlugin(
        id: "com.status.github",
        name: "GitHub",
        author: "Status Foundry",
        description: "Read-only repository checks.",
        category: "developer",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/plugin",
        auth: PackagedPluginAuth(
            type: .bearerToken,
            fields: [
                PackagedPluginSetupField(
                    id: "token",
                    label: "Personal access token",
                    type: .secret,
                    required: true
                )
            ]
        ),
        setup: PackagedPluginSetup(
            title: "Repository",
            fields: [
                PackagedPluginSetupField(id: "owner", label: "Owner", type: .text, required: true),
                PackagedPluginSetupField(id: "repo", label: "Repository", type: .text, required: true)
            ]
        ),
        installedAt: now,
        updatedAt: now
    )
    _ = try PluginSetupConfiguration.saveValues(
        ["token": "token-one", "owner": "statusfoundry", "repo": "status"],
        for: plugin,
        service: service,
        credentialStore: credentials,
        now: now
    )
    _ = try PluginSetupConfiguration.saveValues(
        ["token": "token-two", "owner": "statusfoundry", "repo": "registry"],
        for: plugin,
        service: service,
        credentialStore: credentials,
        now: now
    )
    let statusAccountID = try #require(store.accountConfigurations(pluginID: "com.status.github")
        .first { $0.accountName == "statusfoundry/status" }?.id)

    let message = try PluginSetupConfiguration.saveValues(
        ["token": "token-one-updated", "owner": "statusfoundry", "repo": "status-app"],
        for: plugin,
        service: service,
        credentialStore: credentials,
        accountID: statusAccountID,
        now: now.addingTimeInterval(60)
    )

    let accounts = try store.accountConfigurations(pluginID: "com.status.github")
    let updated = try #require(try store.accountConfiguration(accountID: statusAccountID))
    #expect(message == "Saved statusfoundry/status-app.")
    #expect(accounts.map(\.id).sorted().count == 2)
    #expect(updated.accountName == "statusfoundry/status-app")
    #expect(updated.variables == ["owner": "statusfoundry", "repo": "status-app"])
    #expect(try PluginSetupConfiguration.configuredValues(pluginID: "com.status.github", accountID: statusAccountID, store: store) == [
        "owner": "statusfoundry",
        "repo": "status-app"
    ])
}

@Test func genericPluginSetupStoresAPIKeyCredentialBundleInCredentialStore() throws {
    let database = try temporaryRuntimeDatabase()
    try insertRuntimePluginFixture(database, pluginID: "com.status.weather")
    let store = StatusPersistenceStore(database: database)
    let service = PluginRuntimeService(store: store, credentialStore: nil)
    let credentials = InMemoryCredentialStore()
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let plugin = InstalledPlugin(
        id: "com.status.weather",
        name: "Weather",
        author: "Status Foundry",
        description: "Read-only weather checks.",
        category: "monitoring",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/plugin",
        auth: PackagedPluginAuth(
            type: .apiKey,
            fields: [
                PackagedPluginSetupField(
                    id: "apiKey",
                    label: "API key",
                    type: .secret,
                    required: true
                )
            ],
            placement: PackagedPluginAuthPlacement(name: "X-Weather-Key")
        ),
        setup: PackagedPluginSetup(
            title: "Location",
            fields: [
                PackagedPluginSetupField(id: "city", label: "City", type: .text, required: true)
            ]
        ),
        installedAt: now,
        updatedAt: now
    )

    let message = try PluginSetupConfiguration.saveValues(
        ["apiKey": "weather-secret", "city": "Valletta"],
        for: plugin,
        service: service,
        credentialStore: credentials,
        now: now
    )

    let configuration = try #require(store.accountConfigurations(pluginID: "com.status.weather").first)
    let credentialRef = try #require(configuration.credentialRef)
    let credentialData = try #require(try credentials.read(reference: credentialRef))
    let bundle = try JSONDecoder().decode(PluginAuthCredentialBundle.self, from: credentialData)
    #expect(message == "Saved Valletta.")
    #expect(configuration.authType == "api-key")
    #expect(configuration.variables == ["city": "Valletta"])
    #expect(bundle.fields["apiKey"] == "weather-secret")
}

@Test func genericPluginSetupStoresJWTCredentialBundleInCredentialStore() throws {
    let database = try temporaryRuntimeDatabase()
    try insertRuntimePluginFixture(database, pluginID: "com.status.appstoreconnect")
    let store = StatusPersistenceStore(database: database)
    let service = PluginRuntimeService(store: store, credentialStore: nil)
    let credentials = InMemoryCredentialStore()
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let privateKey = P256.Signing.PrivateKey().pemRepresentation
    let plugin = InstalledPlugin(
        id: "com.status.appstoreconnect",
        name: "App Store Connect",
        author: "Status Foundry",
        description: "Read-only app status.",
        category: "developer",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/plugin",
        auth: PackagedPluginAuth(
            type: .jwtAPIKey,
            fields: [
                PackagedPluginSetupField(id: "issuerId", label: "Issuer ID", type: .text, required: true),
                PackagedPluginSetupField(id: "keyId", label: "Key ID", type: .text, required: true),
                PackagedPluginSetupField(id: "privateKey", label: "Private Key", type: .secretFile, required: true)
            ]
        ),
        installedAt: now,
        updatedAt: now
    )

    let message = try PluginSetupConfiguration.saveValues(
        ["issuerId": "issuer-123", "keyId": "ABC123DEFG", "privateKey": privateKey],
        for: plugin,
        service: service,
        credentialStore: credentials,
        now: now
    )

    let configuration = try #require(store.accountConfigurations(pluginID: "com.status.appstoreconnect").first)
    let credentialRef = try #require(configuration.credentialRef)
    let credentialData = try #require(try credentials.read(reference: credentialRef))
    let bundle = try JSONDecoder().decode(PluginAuthCredentialBundle.self, from: credentialData)
    #expect(message == "Saved App Store Connect.")
    #expect(configuration.authType == "jwt-api-key")
    #expect(configuration.variables == [:])
    #expect(bundle.fields["issuerId"] == "issuer-123")
    #expect(bundle.fields["keyId"] == "ABC123DEFG")
    #expect(bundle.fields["privateKey"] == privateKey)
}

@Test func genericPluginSetupStoresBasicAuthCredentialBundleInCredentialStore() throws {
    let database = try temporaryRuntimeDatabase()
    try insertRuntimePluginFixture(database, pluginID: "com.status.jira")
    let store = StatusPersistenceStore(database: database)
    let service = PluginRuntimeService(store: store, credentialStore: nil)
    let credentials = InMemoryCredentialStore()
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let plugin = InstalledPlugin(
        id: "com.status.jira",
        name: "Jira",
        author: "Status Foundry",
        description: "Read-only Jira checks.",
        category: "developer",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/plugin",
        auth: PackagedPluginAuth(
            type: .basicAuth,
            fields: [
                PackagedPluginSetupField(id: "email", label: "Email", type: .text, required: true),
                PackagedPluginSetupField(id: "apiToken", label: "API token", type: .secret, required: true)
            ]
        ),
        setup: PackagedPluginSetup(
            title: "Site",
            fields: [
                PackagedPluginSetupField(id: "site", label: "Site", type: .hostname, required: true)
            ]
        ),
        installedAt: now,
        updatedAt: now
    )

    let message = try PluginSetupConfiguration.saveValues(
        ["email": "me@example.com", "apiToken": "jira-token", "site": "Example.atlassian.net"],
        for: plugin,
        service: service,
        credentialStore: credentials,
        now: now
    )

    let configuration = try #require(store.accountConfigurations(pluginID: "com.status.jira").first)
    let credentialRef = try #require(configuration.credentialRef)
    let credentialData = try #require(try credentials.read(reference: credentialRef))
    let bundle = try JSONDecoder().decode(PluginAuthCredentialBundle.self, from: credentialData)
    #expect(message == "Saved example.atlassian.net.")
    #expect(configuration.authType == "basic-auth")
    #expect(configuration.variables == ["site": "example.atlassian.net"])
    #expect(bundle.fields["email"] == "me@example.com")
    #expect(bundle.fields["apiToken"] == "jira-token")
}

@Test func pluginRuntimeServiceExecutesProviderBackedActionRequest() async throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let credentials = InMemoryCredentialStore()
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-runtime-action-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: [
        ("auth.json", Data("""
        {
          "type": "basic-auth",
          "fields": [
            { "key": "email", "label": "Email", "type": "text", "required": true },
            { "key": "apiToken", "label": "API token", "type": "secret", "required": true }
          ]
        }
        """.utf8)),
        ("setup.schema.json", Data("""
        {
          "title": "Jira site",
          "fields": [
            { "key": "site", "label": "Site", "type": "hostname", "required": true }
          ]
        }
        """.utf8)),
        ("requests.json", Data("""
        {
          "requests": {
            "create_issue": {
              "method": "POST",
              "url": "https://{{account.site}}/rest/api/3/issue",
              "headers": {
                "Accept": "application/json"
              },
              "body": {
                "fields": {
                  "project": { "key": "{{project}}" },
                  "summary": "{{summary}}",
                  "description": "{{event.summary}}"
                }
              }
            }
          }
        }
        """.utf8)),
        ("actions.json", Data("""
        {
          "actions": [
            {
              "id": "jira.createIssue",
              "label": "Create Jira issue",
              "requiresWritePermission": true,
              "request": "create_issue"
            }
          ]
        }
        """.utf8))
    ])
    try packageData.write(to: packageURL)
    let manifest = PluginManifest(
        id: "com.status.jira",
        name: "Jira",
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "developer",
        description: "Create issues from Status rules.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .keychain, .writeActions],
        domains: ["example.atlassian.net"]
    )
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: try PluginPackageDefinition.decode(from: packageData),
            installedAt: now
        )
    )
    try grantRuntimePermissions(manifest.permissions, pluginID: manifest.id, store: store, at: now)
    let plugin = try #require(try store.installedPlugin(id: manifest.id))
    _ = try PluginSetupConfiguration.saveValues(
        ["email": "me@example.com", "apiToken": "jira-token", "site": "example.atlassian.net"],
        for: plugin,
        service: PluginRuntimeService(store: store, credentialStore: credentials),
        credentialStore: credentials,
        now: now
    )
    let url = try #require(URL(string: "https://example.atlassian.net/rest/api/3/issue"))
    let service = PluginRuntimeService(
        store: store,
        transport: RuntimeActionRequestCheckingTransport(
            response: PluginHTTPResponse(data: Data(#"{"key":"STATUS-1"}"#.utf8), statusCode: 201, url: url),
            expectedURL: url,
            expectedAuthorization: "Basic \(Data("me@example.com:jira-token".utf8).base64EncodedString())"
        ),
        credentialStore: credentials
    )
    let event = Event(
        id: "evt_01workflowfailed",
        provider: "com.status.github",
        type: "github.workflow.failed",
        resourceID: "res_status_repo",
        resourceName: "status",
        severity: .critical,
        title: "Workflow failed",
        summary: "CI failed on main.",
        timestamp: now,
        fingerprint: "github:workflow.failed:res_status_repo:failure"
    )
    let action = ActionRuntimeProviderAction(
        actionRunID: "run_01",
        action: "jira.createIssue",
        provider: event.provider,
        parameters: ["project": "STATUS", "summary": "{{event.title}}"],
        event: event
    )

    let preview = try await service.previewProviderActionRequest(action)

    #expect(preview.pluginID == "com.status.jira")
    #expect(preview.action == "jira.createIssue")
    #expect(preview.requestID == "create_issue")
    #expect(preview.accountID == "acct_com_status_jira_example_atlassian_net")
    #expect(preview.method == "POST")
    #expect(preview.url == url)
    #expect(preview.headers["Accept"] == "application/json")
    #expect(preview.headers["Authorization"] == "<redacted>")
    #expect(preview.headers["Content-Type"] == "application/json")
    #expect(preview.bodyPreview == #"{"fields":{"description":"CI failed on main.","project":{"key":"STATUS"},"summary":"Workflow failed"}}"#)

    let result = try await service.execute(action)

    #expect(result["plugin_id"] == "com.status.jira")
    #expect(result["account_id"] == "acct_com_status_jira_example_atlassian_net")
    #expect(result["request_id"] == "create_issue")
    #expect(result["status_code"] == "201")
    #expect(result["body"] == #"{"key":"STATUS-1"}"#)
}

@Test func pluginRuntimeServiceInjectsAPIKeyHeaderForConfiguredAccount() async throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let credentials = InMemoryCredentialStore()
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-runtime-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: [
        ("auth.json", Data("""
        {
          "type": "api-key",
          "placement": { "in": "header", "name": "X-Weather-Key" },
          "fields": [
            { "key": "apiKey", "label": "API key", "type": "secret", "required": true }
          ]
        }
        """.utf8)),
        ("setup.schema.json", Data("""
        {
          "fields": [
            { "key": "city", "label": "City", "type": "text", "required": true }
          ]
        }
        """.utf8)),
        ("requests.json", Data("""
        {
          "requests": {
            "current_weather": {
              "method": "GET",
              "url": "https://api.weather.example/current",
              "query": { "q": "{{city}}" },
              "auth": "default"
            }
          }
        }
        """.utf8)),
        ("mappings.json", Data("""
        {
          "resources": [],
          "events": []
        }
        """.utf8))
    ])
    try packageData.write(to: packageURL)
    let manifest = PluginManifest(
        id: "com.status.weather",
        name: "Weather",
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "monitoring",
        description: "Read-only weather checks.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .keychain, .backgroundRefresh],
        domains: ["api.weather.example"]
    )
    let definition = try PluginPackageDefinition.decode(from: packageData)
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: definition,
            installedAt: now
        )
    )
    try grantRuntimePermissions(manifest.permissions, pluginID: manifest.id, store: store, at: now)
    try store.upsertTrigger(
        TriggerDefinition(
            id: "trg_com_status_weather_current",
            pluginID: manifest.id,
            kind: .manual,
            label: "Refresh weather",
            requestID: "current_weather"
        ),
        updatedAt: now
    )
    let installed = try #require(try store.installedPlugin(id: manifest.id))
    let setupService = PluginRuntimeService(store: store, credentialStore: nil)
    _ = try PluginSetupConfiguration.saveValues(
        ["apiKey": "weather-secret", "city": "Valletta"],
        for: installed,
        service: setupService,
        credentialStore: credentials,
        now: now
    )
    let url = try #require(URL(string: "https://api.weather.example/current?q=Valletta"))
    let service = PluginRuntimeService(
        store: store,
        transport: RuntimeHeaderValuesCheckingTransport(
            response: PluginHTTPResponse(data: Data("{}".utf8), statusCode: 200, url: url),
            expectedHeaders: ["X-Weather-Key": "weather-secret"]
        ),
        credentialStore: credentials
    )
    let configuration = try #require(store.accountConfigurations(pluginID: manifest.id).first)

    let job = try service.enqueueManualConfiguredPluginRun(pluginID: manifest.id, accountID: configuration.id, now: now)
    _ = try await service.runQueuedPluginJob(jobID: job.id, now: now)

    #expect(try store.job(id: job.id)?.status == .success)
}

@Test func pluginRuntimeServiceInjectsBearerTokenForConfiguredAccount() async throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let credentials = InMemoryCredentialStore()
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-runtime-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: [
        ("auth.json", Data("""
        {
          "type": "bearer-token",
          "fields": [
            { "key": "token", "label": "Token", "type": "secret", "required": true }
          ]
        }
        """.utf8)),
        ("setup.schema.json", Data("""
        {
          "fields": [
            { "key": "owner", "label": "Owner", "type": "text", "required": true },
            { "key": "repo", "label": "Repository", "type": "text", "required": true }
          ]
        }
        """.utf8)),
        ("requests.json", Data("""
        {
          "requests": {
            "list_workflow_runs": {
              "method": "GET",
              "url": "https://api.github.com/repos/{{owner}}/{{repo}}/actions/runs",
              "auth": "default"
            }
          }
        }
        """.utf8)),
        ("mappings.json", Data("""
        {
          "resources": [],
          "events": []
        }
        """.utf8))
    ])
    try packageData.write(to: packageURL)
    let manifest = PluginManifest(
        id: "com.status.github",
        name: "GitHub",
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "developer",
        description: "Read-only GitHub checks.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .keychain, .backgroundRefresh],
        domains: ["api.github.com"]
    )
    let definition = try PluginPackageDefinition.decode(from: packageData)
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: definition,
            installedAt: now
        )
    )
    try grantRuntimePermissions(manifest.permissions, pluginID: manifest.id, store: store, at: now)
    try store.upsertTrigger(
        TriggerDefinition(
            id: "trg_com_status_github_refresh",
            pluginID: manifest.id,
            kind: .manual,
            label: "Refresh GitHub",
            requestID: "list_workflow_runs"
        ),
        updatedAt: now
    )
    let installed = try #require(try store.installedPlugin(id: manifest.id))
    let setupService = PluginRuntimeService(store: store, credentialStore: nil)
    _ = try PluginSetupConfiguration.saveValues(
        ["token": "github_pat_example", "owner": "statusfoundry", "repo": "status"],
        for: installed,
        service: setupService,
        credentialStore: credentials,
        now: now
    )
    let url = try #require(URL(string: "https://api.github.com/repos/statusfoundry/status/actions/runs"))
    let service = PluginRuntimeService(
        store: store,
        transport: RuntimeHeaderCheckingTransport(
            response: PluginHTTPResponse(data: Data("{}".utf8), statusCode: 200, url: url),
            expectedAuthorization: "Bearer github_pat_example"
        ),
        credentialStore: credentials
    )
    let configuration = try #require(store.accountConfigurations(pluginID: manifest.id).first)

    let job = try service.enqueueManualConfiguredPluginRun(pluginID: manifest.id, accountID: configuration.id, now: now)
    _ = try await service.runQueuedPluginJob(jobID: job.id, now: now)

    #expect(try store.job(id: job.id)?.status == .success)
}

@Test func pluginRuntimeServiceInjectsOAuthTokenForConfiguredAccount() async throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let credentials = InMemoryCredentialStore()
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-runtime-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: oauthRuntimePackageFiles())
    try packageData.write(to: packageURL)
    let manifest = oauthRuntimeManifest()
    let definition = try PluginPackageDefinition.decode(from: packageData)
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: definition,
            installedAt: now
        )
    )
    try grantRuntimePermissions(manifest.permissions, pluginID: manifest.id, store: store, at: now)
    try store.upsertTrigger(
        TriggerDefinition(
            id: "trg_com_status_oauth_github_refresh",
            pluginID: manifest.id,
            kind: .manual,
            label: "Refresh GitHub",
            requestID: "list_workflow_runs"
        ),
        updatedAt: now
    )
    let installed = try #require(try store.installedPlugin(id: manifest.id))
    let setupService = PluginRuntimeService(store: store, credentialStore: nil)
    _ = try PluginSetupConfiguration.saveOAuthTokenSet(
        PluginOAuthTokenSet(
            accessToken: "oauth_access",
            refreshToken: "oauth_refresh",
            expiresAt: now.addingTimeInterval(3_600)
        ),
        setupValues: ["owner": "statusfoundry", "repo": "status"],
        for: installed,
        service: setupService,
        credentialStore: credentials,
        now: now
    )
    let url = try #require(URL(string: "https://api.github.com/repos/statusfoundry/status/actions/runs"))
    let service = PluginRuntimeService(
        store: store,
        transport: RuntimeHeaderCheckingTransport(
            response: PluginHTTPResponse(data: Data("{}".utf8), statusCode: 200, url: url),
            expectedAuthorization: "Bearer oauth_access"
        ),
        credentialStore: credentials
    )
    let configuration = try #require(store.accountConfigurations(pluginID: manifest.id).first)

    let job = try service.enqueueManualConfiguredPluginRun(pluginID: manifest.id, accountID: configuration.id, now: now)
    _ = try await service.runQueuedPluginJob(jobID: job.id, now: now)

    #expect(try store.job(id: job.id)?.status == .success)
}

@Test func pluginOAuthExchangesAuthorizationCodeForTokenSet() async throws {
    let auth = PackagedPluginAuth(
        type: .oauth2,
        provider: "github",
        applicationId: "status-foundry.github",
        oauth2: PackagedPluginOAuth2(
            authorizationURL: try #require(URL(string: "https://github.com/login/oauth/authorize")),
            tokenURL: try #require(URL(string: "https://github.com/login/oauth/access_token")),
            redirectURI: "status://oauth/github",
            scopes: ["repo"]
        )
    )
    let request = try PluginOAuth.authorizationRequest(
        pluginID: "com.status.oauthgithub",
        auth: auth,
        state: "state-123",
        codeVerifier: "verifier-123"
    )
    let callback = try #require(URL(string: "status://oauth/github?code=code-456&state=state-123"))
    let tokenURL = try #require(URL(string: "https://github.com/login/oauth/access_token"))
    let now = Date(timeIntervalSince1970: 1_783_433_520)

    let tokenSet = try await PluginOAuth.tokenSet(
        pluginID: "com.status.oauthgithub",
        auth: auth,
        request: request,
        callbackURL: callback,
        transport: RuntimeOAuthCodeExchangeTransport(tokenURL: tokenURL),
        now: now
    )

    #expect(tokenSet.accessToken == "oauth_access")
    #expect(tokenSet.refreshToken == "oauth_refresh")
    #expect(tokenSet.tokenType == "Bearer")
    #expect(tokenSet.scope == "repo")
    #expect(tokenSet.expiresAt == now.addingTimeInterval(3_600))
}

@Test func pluginOAuthRejectsInvalidConfiguredRedirectBeforeAuthorizationURL() throws {
    let auth = PackagedPluginAuth(
        type: .oauth2,
        provider: "github",
        applicationId: "status-foundry.github",
        oauth2: PackagedPluginOAuth2(
            authorizationURL: try #require(URL(string: "https://github.com/login/oauth/authorize")),
            tokenURL: try #require(URL(string: "https://github.com/login/oauth/access_token")),
            redirectURI: "status://oauth/google",
            scopes: ["repo"]
        )
    )

    #expect(throws: PluginOAuthError.invalidRedirectURI("status://oauth/google")) {
        _ = try PluginOAuth.authorizationRequest(
            pluginID: "com.status.oauthgithub",
            auth: auth,
            state: "state-123",
            codeVerifier: "verifier-123"
        )
    }
}

@Test func pluginOAuthRejectsCallbackRedirectMismatchBeforeTokenExchange() async throws {
    let auth = PackagedPluginAuth(
        type: .oauth2,
        provider: "github",
        applicationId: "status-foundry.github",
        oauth2: PackagedPluginOAuth2(
            authorizationURL: try #require(URL(string: "https://github.com/login/oauth/authorize")),
            tokenURL: try #require(URL(string: "https://github.com/login/oauth/access_token")),
            redirectURI: "status://oauth/github",
            scopes: ["repo"]
        )
    )
    let request = try PluginOAuth.authorizationRequest(
        pluginID: "com.status.oauthgithub",
        auth: auth,
        state: "state-123",
        codeVerifier: "verifier-123"
    )
    let callback = try #require(URL(string: "status://oauth/gitlab?code=code-456&state=state-123"))
    let tokenURL = try #require(URL(string: "https://github.com/login/oauth/access_token"))

    await #expect(throws: PluginOAuthError.authorizationRedirectMismatch(expected: "status://oauth/github", actual: "status://oauth/gitlab")) {
        _ = try await PluginOAuth.tokenSet(
            pluginID: "com.status.oauthgithub",
            auth: auth,
            request: request,
            callbackURL: callback,
            transport: RuntimeFailingOAuthTransport(tokenURL: tokenURL)
        )
    }
}

@Test func pluginOAuthRejectsInvalidConfiguredRedirectBeforeTokenExchange() async throws {
    let auth = PackagedPluginAuth(
        type: .oauth2,
        provider: "github",
        applicationId: "status-foundry.github",
        oauth2: PackagedPluginOAuth2(
            authorizationURL: try #require(URL(string: "https://github.com/login/oauth/authorize")),
            tokenURL: try #require(URL(string: "https://github.com/login/oauth/access_token")),
            redirectURI: "status://oauth/google",
            scopes: ["repo"]
        )
    )
    let request = PluginOAuthAuthorizationRequest(
        url: try #require(URL(string: "https://github.com/login/oauth/authorize")),
        codeVerifier: "verifier-123",
        state: "state-123"
    )
    let callback = try #require(URL(string: "status://oauth/google?code=code-456&state=state-123"))
    let tokenURL = try #require(URL(string: "https://github.com/login/oauth/access_token"))

    await #expect(throws: PluginOAuthError.invalidRedirectURI("status://oauth/google")) {
        _ = try await PluginOAuth.tokenSet(
            pluginID: "com.status.oauthgithub",
            auth: auth,
            request: request,
            callbackURL: callback,
            transport: RuntimeFailingOAuthTransport(tokenURL: tokenURL)
        )
    }
}

@Test func pluginRuntimeServiceRefreshesExpiredOAuthTokenBeforeRequest() async throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let credentials = InMemoryCredentialStore()
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-runtime-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: oauthRuntimePackageFiles())
    try packageData.write(to: packageURL)
    let manifest = oauthRuntimeManifest()
    let definition = try PluginPackageDefinition.decode(from: packageData)
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: definition,
            installedAt: now
        )
    )
    try grantRuntimePermissions(manifest.permissions, pluginID: manifest.id, store: store, at: now)
    try store.upsertTrigger(
        TriggerDefinition(
            id: "trg_com_status_oauth_github_refresh",
            pluginID: manifest.id,
            kind: .manual,
            label: "Refresh GitHub",
            requestID: "list_workflow_runs"
        ),
        updatedAt: now
    )
    let installed = try #require(try store.installedPlugin(id: manifest.id))
    let setupService = PluginRuntimeService(store: store, credentialStore: nil)
    _ = try PluginSetupConfiguration.saveOAuthTokenSet(
        PluginOAuthTokenSet(
            accessToken: "expired_access",
            refreshToken: "old_refresh",
            expiresAt: now.addingTimeInterval(-60)
        ),
        setupValues: ["owner": "statusfoundry", "repo": "status"],
        for: installed,
        service: setupService,
        credentialStore: credentials,
        now: now
    )
    let apiURL = try #require(URL(string: "https://api.github.com/repos/statusfoundry/status/actions/runs"))
    let tokenURL = try #require(URL(string: "https://github.com/login/oauth/access_token"))
    let service = PluginRuntimeService(
        store: store,
        transport: RuntimeOAuthRefreshTransport(apiURL: apiURL, tokenURL: tokenURL),
        credentialStore: credentials
    )
    let configuration = try #require(store.accountConfigurations(pluginID: manifest.id).first)

    let job = try service.enqueueManualConfiguredPluginRun(pluginID: manifest.id, accountID: configuration.id, now: now)
    _ = try await service.runQueuedPluginJob(jobID: job.id, now: now)

    let storedConfiguration = try store.accountConfiguration(accountID: configuration.id)
    let updated = try #require(storedConfiguration)
    let updatedReference = try #require(updated.credentialRef)
    let tokenData = try #require(try credentials.read(reference: updatedReference))
    let tokenSet = try JSONDecoder().decode(PluginOAuthTokenSet.self, from: tokenData)
    #expect(try store.job(id: job.id)?.status == .success)
    #expect(tokenSet.accessToken == "fresh_access")
    #expect(tokenSet.refreshToken == "new_refresh")
    #expect(tokenSet.expiresAt == now.addingTimeInterval(3_600))
}

@Test func pluginRuntimeServiceInjectsBasicAuthForConfiguredAccount() async throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let credentials = InMemoryCredentialStore()
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-runtime-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: [
        ("auth.json", Data("""
        {
          "type": "basic-auth",
          "fields": [
            { "key": "email", "label": "Email", "type": "text", "required": true },
            { "key": "apiToken", "label": "API token", "type": "secret", "required": true }
          ]
        }
        """.utf8)),
        ("setup.schema.json", Data("""
        {
          "fields": [
            { "key": "site", "label": "Site", "type": "hostname", "required": true }
          ]
        }
        """.utf8)),
        ("requests.json", Data("""
        {
          "requests": {
            "search_issues": {
              "method": "GET",
              "url": "https://{{site}}/rest/api/3/search",
              "auth": "default"
            }
          }
        }
        """.utf8)),
        ("mappings.json", Data("""
        {
          "resources": [],
          "events": []
        }
        """.utf8))
    ])
    try packageData.write(to: packageURL)
    let manifest = PluginManifest(
        id: "com.status.jira",
        name: "Jira",
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "developer",
        description: "Read-only Jira checks.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .keychain, .backgroundRefresh],
        domains: ["example.atlassian.net"]
    )
    let definition = try PluginPackageDefinition.decode(from: packageData)
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: definition,
            installedAt: now
        )
    )
    try grantRuntimePermissions(manifest.permissions, pluginID: manifest.id, store: store, at: now)
    try store.upsertTrigger(
        TriggerDefinition(
            id: "trg_com_status_jira_search",
            pluginID: manifest.id,
            kind: .manual,
            label: "Refresh Jira",
            requestID: "search_issues"
        ),
        updatedAt: now
    )
    let installed = try #require(try store.installedPlugin(id: manifest.id))
    let setupService = PluginRuntimeService(store: store, credentialStore: nil)
    _ = try PluginSetupConfiguration.saveValues(
        ["email": "me@example.com", "apiToken": "jira-token", "site": "example.atlassian.net"],
        for: installed,
        service: setupService,
        credentialStore: credentials,
        now: now
    )
    let url = try #require(URL(string: "https://example.atlassian.net/rest/api/3/search"))
    let expectedAuthorization = "Basic \(Data("me@example.com:jira-token".utf8).base64EncodedString())"
    let service = PluginRuntimeService(
        store: store,
        transport: RuntimeHeaderCheckingTransport(
            response: PluginHTTPResponse(data: Data("{}".utf8), statusCode: 200, url: url),
            expectedAuthorization: expectedAuthorization
        ),
        credentialStore: credentials
    )
    let configuration = try #require(store.accountConfigurations(pluginID: manifest.id).first)

    let job = try service.enqueueManualConfiguredPluginRun(pluginID: manifest.id, accountID: configuration.id, now: now)
    _ = try await service.runQueuedPluginJob(jobID: job.id, now: now)

    #expect(try store.job(id: job.id)?.status == .success)
}

@Test func pluginRuntimeServiceInjectsJWTForConfiguredAppStoreConnectAccount() async throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let credentials = InMemoryCredentialStore()
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let privateKey = P256.Signing.PrivateKey().pemRepresentation
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-runtime-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: [
        ("auth.json", Data("""
        {
          "type": "jwt-api-key",
          "fields": [
            { "key": "issuerId", "label": "Issuer ID", "type": "text", "required": true },
            { "key": "keyId", "label": "Key ID", "type": "text", "required": true },
            { "key": "privateKey", "label": "Private Key", "type": "secret-file", "required": true }
          ]
        }
        """.utf8)),
        ("requests.json", Data("""
        {
          "requests": {
            "list_apps": {
              "method": "GET",
              "url": "https://api.appstoreconnect.apple.com/v1/apps",
              "auth": "default"
            }
          }
        }
        """.utf8)),
        ("mappings.json", Data("""
        {
          "resources": [],
          "events": []
        }
        """.utf8))
    ])
    try packageData.write(to: packageURL)
    let manifest = PluginManifest(
        id: "com.status.appstoreconnect",
        name: "App Store Connect",
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "developer",
        description: "Read-only App Store Connect checks.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .keychain, .privateKey, .backgroundRefresh],
        domains: ["api.appstoreconnect.apple.com"]
    )
    let definition = try PluginPackageDefinition.decode(from: packageData)
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: definition,
            installedAt: now
        )
    )
    try grantRuntimePermissions(manifest.permissions, pluginID: manifest.id, store: store, at: now)
    try store.upsertTrigger(
        TriggerDefinition(
            id: "trg_com_status_appstoreconnect_refresh",
            pluginID: manifest.id,
            kind: .manual,
            label: "Refresh apps",
            requestID: "list_apps"
        ),
        updatedAt: now
    )
    let installed = try #require(try store.installedPlugin(id: manifest.id))
    let setupService = PluginRuntimeService(store: store, credentialStore: nil)
    _ = try PluginSetupConfiguration.saveValues(
        ["issuerId": "issuer-123", "keyId": "ABC123DEFG", "privateKey": privateKey],
        for: installed,
        service: setupService,
        credentialStore: credentials,
        now: now
    )
    let url = try #require(URL(string: "https://api.appstoreconnect.apple.com/v1/apps"))
    let service = PluginRuntimeService(
        store: store,
        transport: RuntimeAuthorizationCheckingTransport(
            response: PluginHTTPResponse(data: Data("{}".utf8), statusCode: 200, url: url),
            validate: { authorization in
                #expect(authorization?.hasPrefix("Bearer ") == true)
                let token = try #require(authorization?.dropFirst("Bearer ".count))
                #expect(token.split(separator: ".").count == 3)
            }
        ),
        credentialStore: credentials
    )
    let configuration = try #require(store.accountConfigurations(pluginID: manifest.id).first)

    let job = try service.enqueueManualConfiguredPluginRun(pluginID: manifest.id, accountID: configuration.id, now: now)
    _ = try await service.runQueuedPluginJob(jobID: job.id, now: now)

    #expect(try store.job(id: job.id)?.status == .success)
}

@Test func websitePluginSetupNormalizesAndSavesHostConfiguration() throws {
    let database = try temporaryRuntimeDatabase()
    try insertRuntimePluginFixture(database, pluginID: WebsitePluginSetup.pluginID)
    let store = StatusPersistenceStore(database: database)
    let service = PluginRuntimeService(store: store)

    let message = try WebsitePluginSetup.saveHost(
        " HTTPS://Status-Registry.Hakobs.Com/ ",
        service: service
    )

    #expect(message == "Saved status-registry.hakobs.com.")
    #expect(try WebsitePluginSetup.configuredHost(store: store) == "status-registry.hakobs.com")
    #expect(try WebsitePluginSetup.configuredAccount(store: store) == PluginAccountConfiguration(
        id: "acct_website_status_registry_hakobs_com",
        pluginID: "com.status.website",
        accountName: "status-registry.hakobs.com",
        variables: ["host": "status-registry.hakobs.com"]
    ))
}

@Test func genericPluginSetupSavesPlainConfigurationValues() throws {
    let database = try temporaryRuntimeDatabase()
    try insertRuntimePluginFixture(database, pluginID: WebsitePluginSetup.pluginID)
    let store = StatusPersistenceStore(database: database)
    let service = PluginRuntimeService(store: store)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let plugin = InstalledPlugin(
        id: WebsitePluginSetup.pluginID,
        name: "Website Uptime",
        author: "Status Foundry",
        description: "Check a site.",
        category: "monitoring",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/plugin",
        setup: PackagedPluginSetup(
            title: "Website",
            fields: [
                PackagedPluginSetupField(
                    id: "host",
                    label: "Host",
                    type: .hostname,
                    required: true
                )
            ]
        ),
        installedAt: now,
        updatedAt: now
    )

    let message = try PluginSetupConfiguration.saveValues(
        ["host": " HTTPS://Status-Registry.Hakobs.Com/ "],
        for: plugin,
        service: service,
        now: now
    )

    #expect(message == "Saved status-registry.hakobs.com.")
    #expect(try PluginSetupConfiguration.configuredValues(pluginID: WebsitePluginSetup.pluginID, store: store) == [
        "host": "status-registry.hakobs.com"
    ])
    #expect(try store.accountConfigurations(pluginID: WebsitePluginSetup.pluginID).first?.id == "acct_com_status_website_status_registry_hakobs_com")
}

@Test func websitePluginSetupRejectsInvalidHosts() throws {
    #expect(throws: WebsitePluginSetupError.invalidHost) {
        try WebsitePluginSetup.normalizedHost("localhost")
    }
    #expect(throws: WebsitePluginSetupError.invalidHost) {
        try WebsitePluginSetup.normalizedHost("example.com:443")
    }
    #expect(throws: WebsitePluginSetupError.invalidHost) {
        try WebsitePluginSetup.normalizedHost("example.com/path")
    }
}

private struct RuntimeFakeTransport: PluginRequestHTTPTransport {
    var responses: [URL: PluginHTTPResponse]

    func response(for request: PluginHTTPRequest) async throws -> PluginHTTPResponse {
        try #require(responses[request.url])
    }
}

private struct RuntimeFailingTransport: PluginRequestHTTPTransport {
    func response(for request: PluginHTTPRequest) async throws -> PluginHTTPResponse {
        throw PluginRuntimeServiceTestError.transportUnavailable
    }
}

private enum PluginRuntimeServiceTestError: Error {
    case transportUnavailable
}

private struct RuntimeHeaderCheckingTransport: PluginRequestHTTPTransport {
    var response: PluginHTTPResponse
    var expectedAuthorization: String

    func response(for request: PluginHTTPRequest) async throws -> PluginHTTPResponse {
        #expect(request.headers["Authorization"] == expectedAuthorization)
        return response
    }
}

private struct RuntimeHeaderValuesCheckingTransport: PluginRequestHTTPTransport {
    var response: PluginHTTPResponse
    var expectedHeaders: [String: String]

    func response(for request: PluginHTTPRequest) async throws -> PluginHTTPResponse {
        for (name, value) in expectedHeaders {
            #expect(request.headers[name] == value)
        }
        return response
    }
}

private struct RuntimeAuthorizationCheckingTransport: PluginRequestHTTPTransport {
    var response: PluginHTTPResponse
    var validate: @Sendable (String?) throws -> Void

    func response(for request: PluginHTTPRequest) async throws -> PluginHTTPResponse {
        try validate(request.headers["Authorization"])
        return response
    }
}

private struct RuntimeActionRequestCheckingTransport: PluginRequestHTTPTransport {
    var response: PluginHTTPResponse
    var expectedURL: URL
    var expectedAuthorization: String

    func response(for request: PluginHTTPRequest) async throws -> PluginHTTPResponse {
        #expect(request.method == "POST")
        #expect(request.url == expectedURL)
        #expect(request.headers["Authorization"] == expectedAuthorization)
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.headers["Content-Type"] == "application/json")
        let body = try #require(request.body)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let fields = try #require(object["fields"] as? [String: Any])
        let project = try #require(fields["project"] as? [String: Any])
        #expect(project["key"] as? String == "STATUS")
        #expect(fields["summary"] as? String == "Workflow failed")
        #expect(fields["description"] as? String == "CI failed on main.")
        return response
    }
}

private struct RuntimeOAuthRefreshTransport: PluginRequestHTTPTransport {
    var apiURL: URL
    var tokenURL: URL

    func response(for request: PluginHTTPRequest) async throws -> PluginHTTPResponse {
        if request.url == tokenURL {
            #expect(request.method == "POST")
            #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded")
            let body = try #require(request.body.flatMap { String(data: $0, encoding: .utf8) })
            #expect(body.contains("client_id=status-foundry.github"))
            #expect(body.contains("grant_type=refresh_token"))
            #expect(body.contains("refresh_token=old_refresh"))
            return PluginHTTPResponse(
                data: Data("""
                {
                  "access_token": "fresh_access",
                  "refresh_token": "new_refresh",
                  "token_type": "Bearer",
                  "expires_in": 3600,
                  "scope": "repo"
                }
                """.utf8),
                statusCode: 200,
                url: tokenURL
            )
        }
        #expect(request.url == apiURL)
        #expect(request.headers["Authorization"] == "Bearer fresh_access")
        return PluginHTTPResponse(data: Data("{}".utf8), statusCode: 200, url: apiURL)
    }
}

private struct RuntimeOAuthCodeExchangeTransport: PluginRequestHTTPTransport {
    var tokenURL: URL

    func response(for request: PluginHTTPRequest) async throws -> PluginHTTPResponse {
        #expect(request.method == "POST")
        #expect(request.url == tokenURL)
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded")
        let body = try #require(request.body.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains("client_id=status-foundry.github"))
        #expect(body.contains("code=code-456"))
        #expect(body.contains("code_verifier=verifier-123"))
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("redirect_uri=status%3A%2F%2Foauth%2Fgithub"))
        return PluginHTTPResponse(
            data: Data("""
            {
              "access_token": "oauth_access",
              "refresh_token": "oauth_refresh",
              "token_type": "Bearer",
              "expires_in": 3600,
              "scope": "repo"
            }
            """.utf8),
            statusCode: 200,
            url: tokenURL
        )
    }
}

private struct RuntimeFailingOAuthTransport: PluginRequestHTTPTransport {
    var tokenURL: URL

    func response(for request: PluginHTTPRequest) async throws -> PluginHTTPResponse {
        Issue.record("OAuth token exchange should not run for redirect mismatch.")
        return PluginHTTPResponse(data: Data("{}".utf8), statusCode: 500, url: tokenURL)
    }
}

private func oauthRuntimeManifest() -> PluginManifest {
    PluginManifest(
        id: "com.status.oauthgithub",
        name: "OAuth GitHub",
        version: "0.1.0",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        category: "developer",
        description: "OAuth-backed GitHub checks.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .keychain, .oauth, .backgroundRefresh],
        domains: ["api.github.com", "github.com"]
    )
}

private func oauthRuntimePackageFiles() -> [(String, Data)] {
    [
        ("auth.json", Data("""
        {
          "type": "oauth2",
          "provider": "github",
          "applicationId": "status-foundry.github",
          "oauth2": {
            "authorizationUrl": "https://github.com/login/oauth/authorize",
            "tokenUrl": "https://github.com/login/oauth/access_token",
            "redirectUri": "status://oauth/github",
            "scopes": ["repo"]
          }
        }
        """.utf8)),
        ("setup.schema.json", Data("""
        {
          "fields": [
            { "key": "owner", "label": "Owner", "type": "text", "required": true },
            { "key": "repo", "label": "Repository", "type": "text", "required": true }
          ]
        }
        """.utf8)),
        ("requests.json", Data("""
        {
          "requests": {
            "list_workflow_runs": {
              "method": "GET",
              "url": "https://api.github.com/repos/{{owner}}/{{repo}}/actions/runs",
              "auth": "default"
            }
          }
        }
        """.utf8)),
        ("mappings.json", Data("""
        {
          "resources": [],
          "events": []
        }
        """.utf8))
    ]
}

private func temporaryRuntimeDatabase() throws -> SQLiteDatabase {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-\(UUID().uuidString).sqlite")
        .path
    let database = try SQLiteDatabase(path: path)
    try StatusDatabaseMigrator.migrate(database)
    return database
}

private func insertRuntimePluginFixture(_ database: SQLiteDatabase, pluginID: String) throws {
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

private func grantRuntimePermissions(_ permissions: [PluginPermission], pluginID: String, store: StatusPersistenceStore, at date: Date) throws {
    for permission in permissions {
        try store.setPluginPermission(pluginID: pluginID, permission: permission, granted: true, grantedAt: date)
    }
}

private final class RecordingCredentialStore: CredentialStore, @unchecked Sendable {
    private(set) var storedReferences: [String] = []
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    func store(_ data: Data, label: String) throws -> String {
        let reference = try CredentialReference.make()
        lock.lock()
        storedReferences.append(reference)
        storage[reference] = data
        lock.unlock()
        return reference
    }

    func read(reference: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[reference]
    }

    func delete(reference: String) throws {
        lock.lock()
        storage[reference] = nil
        lock.unlock()
    }
}

private func runtimeStoredZip(files: [(String, Data)]) -> Data {
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
