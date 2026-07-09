import Foundation
import Testing
import StatusCore
@testable import StatusUI

@MainActor
@Test func pluginStoreViewModelLoadsRuntimeStatusesForInstalledPlugins() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.github",
        name: "GitHub",
        author: "Status Foundry",
        description: "GitHub repository checks.",
        category: "development",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.github",
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let runtimeStatus = PluginRuntimeStatus(
        pluginID: plugin.id,
        status: .failed,
        detail: "Missing network permission.",
        timestamp: Date(timeIntervalSince1970: 1_783_433_530)
    )
    var loadedStatusPluginIDs: [[String]] = []
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        loadRuntimeStatuses: { plugins in
            loadedStatusPluginIDs.append(plugins.map(\.id))
            return [plugin.id: runtimeStatus]
        },
        installPlugin: { _ in }
    )

    await viewModel.reload()

    #expect(loadedStatusPluginIDs == [[plugin.id]])
    #expect(viewModel.runtimeStatuses == [plugin.id: runtimeStatus])
}

@MainActor
@Test func pluginStoreViewModelLoadsResourcesForInstalledPlugins() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.website",
        name: "Website",
        author: "Status Foundry",
        description: "Website checks.",
        category: "operations",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.website",
        views: [
            PackagedPluginView(
                id: "websites",
                type: .resourceList,
                resourceType: "website",
                fields: ["statusCode"]
            )
        ],
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let resource = Resource(
        id: "res_com_status_website_example",
        accountID: "acc_website",
        pluginID: plugin.id,
        type: "website",
        name: "example.com",
        fields: ["statusCode": "200"]
    )
    var loadedResourcePluginIDs: [String] = []
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        loadRuntimeStatuses: { _ in [:] },
        loadPluginResources: { plugin in
            loadedResourcePluginIDs.append(plugin.id)
            return [resource]
        },
        installPlugin: { _ in }
    )

    await viewModel.reload()

    #expect(loadedResourcePluginIDs == [plugin.id])
    #expect(viewModel.pluginResources == [plugin.id: [resource]])
}
