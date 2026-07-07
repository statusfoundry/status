import Foundation

public enum MockDashboard {
    public static let snapshot: DashboardSnapshot = {
        let now = Date(timeIntervalSince1970: 1_783_433_520)
        let appURL = URL(string: "https://appstoreconnect.apple.com")!
        let workflowURL = URL(string: "https://github.com/statusfoundry/status/actions")!

        return DashboardSnapshot(
            headline: "1 critical item",
            summary: "Most products are okay. One workflow needs attention and one app is waiting for review.",
            statusItems: [
                StatusItem(
                    id: "sti_01statusworkflowfailed",
                    resourceID: "res_status_repo",
                    severity: .critical,
                    title: "GitHub workflow failed",
                    summary: "The main branch build failed after the latest documentation tooling commit.",
                    state: .open,
                    updatedAt: now,
                    actionLink: ActionLink(id: "act_open_workflow", label: "Open workflow", url: workflowURL)
                ),
                StatusItem(
                    id: "sti_01appwaiting",
                    resourceID: "res_tiko_app",
                    severity: .warning,
                    title: "Tiko Yes No waiting for review",
                    summary: "The current App Store version is waiting for Apple review.",
                    state: .open,
                    updatedAt: now.addingTimeInterval(-3_600),
                    actionLink: ActionLink(id: "act_open_asc", label: "Open App Store Connect", url: appURL)
                )
            ],
            recentEvents: [
                Event(
                    id: "evt_01workflowfailed",
                    provider: "github",
                    type: "github.workflow.failed",
                    resourceID: "res_status_repo",
                    resourceName: "status",
                    severity: .critical,
                    title: "Workflow failed",
                    summary: "CI failed on main.",
                    timestamp: now,
                    actionURL: workflowURL,
                    fingerprint: "github:workflow.failed:res_status_repo:main"
                ),
                Event(
                    id: "evt_01appwaiting",
                    provider: "appstoreconnect",
                    type: "app.review.waiting_for_review",
                    resourceID: "res_tiko_app",
                    resourceName: "Tiko Yes No",
                    severity: .warning,
                    title: "App waiting for review",
                    summary: "A submitted version is waiting for review.",
                    timestamp: now.addingTimeInterval(-3_600),
                    actionURL: appURL,
                    fingerprint: "appstoreconnect:app.review.waiting_for_review:res_tiko_app:WAITING"
                )
            ],
            metrics: [
                Metric(id: "met_uptime", resourceID: "res_status_site", label: "Uptime", value: "100%", delta: "24h", severity: .ok),
                Metric(id: "met_events", resourceID: "res_status", label: "New events", value: "4", delta: "today", severity: .notice),
                Metric(id: "met_actions", resourceID: "res_status", label: "Actions run", value: "1", delta: "audited", severity: .ok)
            ],
            integrations: [
                IntegrationSummary(id: "int_appstore", name: "App Store Connect", provider: "appstoreconnect", state: "Connected", severity: .warning, lastSyncDescription: "15 min ago"),
                IntegrationSummary(id: "int_github", name: "GitHub", provider: "github", state: "Needs attention", severity: .critical, lastSyncDescription: "2 min ago"),
                IntegrationSummary(id: "int_uptime", name: "Website uptime", provider: "website", state: "Okay", severity: .ok, lastSyncDescription: "1 min ago")
            ],
            auditEntries: [
                AuditEntry(
                    id: "aud_01notification",
                    title: "Notification queued",
                    detail: "Rule matched github.workflow.failed and queued a local notification.",
                    timestamp: now,
                    status: "success",
                    eventID: "evt_01workflowfailed",
                    actionRunID: "run_rul_notify_evt_01workflowfailed_0"
                ),
                AuditEntry(
                    id: "aud_01job",
                    title: "Job completed",
                    detail: "com.status.github job job_poll_01 from trigger trg_github is success. Emitted events: evt_01workflowfailed.",
                    timestamp: now.addingTimeInterval(-120),
                    status: "success",
                    jobID: "job_poll_01",
                    eventID: "evt_01workflowfailed"
                )
            ]
        )
    }()
}
