import Foundation
import Testing
@testable import StatusCore

@Test func pluginMappingExecutorMapsResourcesFromRequestPayload() throws {
    let mappings = PackagedPluginMappings(resources: [
        PackagedResourceMapping(
            type: "app",
            request: "list_apps",
            source: "$.data[*]",
            id: "$.id",
            name: "$.attributes.name",
            fields: [
                "bundleId": "$.attributes.bundleId",
                "sku": "$.attributes.sku"
            ],
            actionURL: "https://appstoreconnect.apple.com/apps/{{id}}/appstore"
        )
    ])
    let output = try PluginMappingExecutor.execute(
        mappings,
        input: PluginMappingExecutionInput(
            pluginID: "com.status.appstoreconnect",
            accountID: "acct_asc",
            provider: "com.status.appstoreconnect",
            requestID: "list_apps",
            payload: decodeMappingJSON("""
            {
              "data": [
                {
                  "id": "123",
                  "attributes": {
                    "name": "Status",
                    "bundleId": "com.status.app",
                    "sku": "STATUS"
                  }
                }
              ]
            }
            """),
            capturedAt: Date(timeIntervalSince1970: 1_783_433_520)
        )
    )

    #expect(output.resources.count == 1)
    #expect(output.resources[0].resource.id == "acct_asc:123")
    #expect(output.resources[0].resource.name == "Status")
    #expect(output.resources[0].resource.actionURL?.absoluteString == "https://appstoreconnect.apple.com/apps/123/appstore")
    #expect(output.resources[0].state == [
        "id": "123",
        "name": "Status",
        "bundleId": "com.status.app",
        "sku": "STATUS"
    ])
}

@Test func pluginMappingExecutorEmitsEventsForMatchingBundledStyleConditions() throws {
    let mappings = PackagedPluginMappings(events: [
        PackagedEventMapping(
            type: "website.down",
            request: "check_site",
            when: .shorthand("$.statusCode >= 500 || $.reachable == false"),
            resourceID: "{{host}}",
            title: "Website down",
            summary: "{{host}} is not responding normally.",
            severity: .fixed(.critical),
            actionURL: "https://{{host}}"
        ),
        PackagedEventMapping(
            type: "website.recovered",
            request: "check_site",
            when: .shorthand("$.previousHealthy == false && $.reachable == true"),
            resourceID: "{{host}}",
            title: "Website recovered",
            summary: "{{host}} is healthy again.",
            severity: .fixed(.ok),
            actionURL: "https://{{host}}"
        )
    ])

    let output = try PluginMappingExecutor.execute(
        mappings,
        input: PluginMappingExecutionInput(
            pluginID: "com.status.website",
            accountID: "acct_web",
            provider: "com.status.website",
            requestID: "check_site",
            payload: decodeMappingJSON("""
            {
              "host": "status.hakobs.com",
              "statusCode": 503,
              "reachable": true,
              "previousHealthy": false
            }
            """),
            capturedAt: Date(timeIntervalSince1970: 1_783_433_520)
        )
    )

    #expect(output.events.map(\.type) == ["website.down", "website.recovered"])
    #expect(output.events[0].resourceID == "acct_web:status.hakobs.com")
    #expect(output.events[0].severity == .critical)
    #expect(output.events[0].summary == "status.hakobs.com is not responding normally.")
    #expect(output.events[0].actionURL?.absoluteString == "https://status.hakobs.com")
    #expect(output.events[1].severity == .ok)
}

@Test func pluginMappingExecutorMapsSelectorActionURLAndTimestamp() throws {
    let mappings = PackagedPluginMappings(events: [
        PackagedEventMapping(
            type: "github.pull_request.opened",
            request: "list_repository_activity",
            source: "$[*]",
            when: .shorthand("$.type == 'PullRequestEvent' && $.payload.action == 'opened'"),
            resourceID: "$.repo.id",
            title: "Pull request opened",
            summary: "{{actor.login}} opened a pull request.",
            severity: .fixed(.notice),
            actionURL: "$.payload.pull_request.html_url",
            timestamp: "$.created_at"
        )
    ])
    let output = try PluginMappingExecutor.execute(
        mappings,
        input: PluginMappingExecutionInput(
            pluginID: "com.status.github",
            accountID: "acct_gh",
            provider: "com.status.github",
            requestID: "list_repository_activity",
            payload: decodeMappingJSON("""
            [
              {
                "type": "PullRequestEvent",
                "repo": { "id": "repo-1", "name": "statusfoundry/status" },
                "actor": { "login": "sil" },
                "created_at": "2026-07-07T20:15:30Z",
                "payload": {
                  "action": "opened",
                  "pull_request": {
                    "html_url": "https://github.com/statusfoundry/status/pull/1"
                  }
                }
              }
            ]
            """),
            capturedAt: Date(timeIntervalSince1970: 1_783_433_520)
        )
    )

    #expect(output.events.count == 1)
    #expect(output.events[0].resourceID == "acct_gh:repo-1")
    #expect(output.events[0].summary == "sil opened a pull request.")
    #expect(output.events[0].actionURL?.absoluteString == "https://github.com/statusfoundry/status/pull/1")
    #expect(output.events[0].timestamp == ISO8601DateFormatter().date(from: "2026-07-07T20:15:30Z"))
}

@Test func pluginMappingExecutorMapsNumericMetrics() throws {
    let mappings = PackagedPluginMappings(metrics: [
        PackagedMetricMapping(
            request: "channel_stats",
            source: "$.items[*]",
            name: "views_28d",
            resourceID: "$.id",
            value: "$.statistics.viewCount",
            unit: "count",
            timestamp: "$.capturedAt"
        )
    ])
    let output = try PluginMappingExecutor.execute(
        mappings,
        input: PluginMappingExecutionInput(
            pluginID: "com.status.youtube",
            accountID: "acct_yt",
            provider: "com.status.youtube",
            requestID: "channel_stats",
            payload: decodeMappingJSON("""
            {
              "items": [
                {
                  "id": "channel-1",
                  "capturedAt": "2026-07-07T20:15:30Z",
                  "statistics": {
                    "viewCount": "1234"
                  }
                }
              ]
            }
            """),
            capturedAt: Date(timeIntervalSince1970: 1_783_433_520)
        )
    )

    #expect(output.metrics.count == 1)
    #expect(output.metrics[0].metric.id == "acct_yt:channel-1:metric:views_28d")
    #expect(output.metrics[0].metric.resourceID == "acct_yt:channel-1")
    #expect(output.metrics[0].metric.label == "views_28d")
    #expect(output.metrics[0].metric.value == "1234")
    #expect(output.metrics[0].metric.delta == "count")
    #expect(output.metrics[0].pointValue == 1234)
    #expect(output.metrics[0].pointTimestamp == ISO8601DateFormatter().date(from: "2026-07-07T20:15:30Z"))
}

private func decodeMappingJSON(_ string: String) throws -> MappingJSONValue {
    try JSONDecoder().decode(MappingJSONValue.self, from: Data(string.utf8))
}
