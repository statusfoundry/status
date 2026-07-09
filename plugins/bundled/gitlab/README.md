# GitLab

Read-only GitLab project events for failed pipelines, merge requests, issues, and project activity.

## Why install this plugin

Install GitLab when you track delivery work in GitLab projects and want failed pipelines, new merge requests, and new issues to surface in Status alongside your other operational signals. The plugin links back to GitLab pages for deep work while Status owns notifications and inbox routing.

## What you configure

Create one configured app per GitLab project:

- **Project ID or URL-encoded path** — numeric project ID (for example `278964`) or encoded namespace path (for example `group%2Fproject`)

Status stores a GitLab `PRIVATE-TOKEN` in Keychain through the shared plugin auth flow.

## What it exposes

### Resources

- **project** — the tracked GitLab project and its latest pipeline/activity context

### Events

| Event | Meaning | Default notification |
| --- | --- | --- |
| `gitlab.pipeline.failed` | A project pipeline completed with a failed status | Dashboard only |
| `gitlab.merge_request.opened` | A merge request was opened on the tracked project | Digest |
| `gitlab.issue.opened` | An issue was opened on the tracked project | Digest |

### Views

- **Projects** — resource list of tracked GitLab projects
- **Recent Project Activity** — timeline of recent project events

### Checks

- **Check pipelines** — cron schedule every 15 minutes
- **Refresh project** — manual project refresh
- **Refresh project activity** — manual activity refresh

## Suggested automations

Suggested rules ship disabled. Enable presets after install if you want inbox or notification routing for failed pipelines.

## Actions

Read-only in v1. No pipeline retry, merge, or issue mutation actions.

## Permissions and domains

- `network` — call GitLab HTTPS APIs
- `keychain` — store the private token securely
- `background-refresh` — run scheduled pipeline checks
- **Domains:** `gitlab.com`

## What it does not do

- Does not replace GitLab's project dashboard
- Does not retry pipelines, merge requests, or modify issues automatically
- Does not support self-managed GitLab domains in this package yet

## Setup

1. Install **GitLab** from the Status plugin store.
2. Create a configured app and enter the project ID or encoded path.
3. Add a GitLab personal access token with read access to the project.
4. Grant network and background refresh permissions.
5. Run **Refresh project**, then enable **Check pipelines** for scheduled polling.