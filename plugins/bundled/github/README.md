# GitHub

Read-only GitHub repository events for workflow failures, pull requests, and issue activity.

## Why install this plugin

Install GitHub when you need a calm operational signal above your repositories — especially failing workflows and fresh pull request activity — without living inside the GitHub UI. Status normalizes repository state into events, inbox items, and native views so you can see what changed and open the provider when action is needed.

## What you configure

Create one configured app per repository you want to watch:

- **Owner** — GitHub user or organization name
- **Repository** — repository name

Status connects GitHub with OAuth device flow. The plugin declares GitHub's device authorization and token endpoints, Status opens GitHub for user approval, and the resulting token set is stored in Keychain. The plugin only calls declared `api.github.com` endpoints.

Official builds should ship the public GitHub OAuth client ID in `auth.json` so users do not need to paste an app ID. Local development builds can override that public client ID in setup with a GitHub OAuth App that has device flow enabled. No GitHub client secret belongs in the plugin package or native app.

## What it exposes

### Resources

- **repository** — the tracked repository and its latest activity context

### Events

| Event | Meaning | Default notification |
| --- | --- | --- |
| `github.workflow.failed` | A GitHub Actions workflow run completed with a failure | Dashboard only |
| `github.pull_request.opened` | A pull request was opened on the tracked repository | Digest |

### Views

- **Repositories** — resource list of tracked repositories
- **Recent Repository Activity** — timeline of recent repository activity

### Checks

- **Check workflow runs** — cron schedule every 15 minutes
- **Refresh repository activity** — manual refresh on demand

## Suggested automations

- **Notify on failed workflows** — adds workflow failures to the Status inbox and can show a local notification when you enable the preset

All suggested rules install disabled.

## Actions

Read-only in v1. No merge, close, or branch mutation actions.

## Permissions and domains

- `network` — poll GitHub HTTPS APIs
- `keychain` — store the GitHub OAuth token securely
- `oauth` — connect GitHub through OAuth device flow
- `background-refresh` — run scheduled workflow checks
- **Domains:** `api.github.com`, `github.com`

## What it does not do

- Does not replace the GitHub dashboard or Actions UI
- Does not merge pull requests, close issues, or modify branches
- Does not receive webhooks in the current package (polling only)

## Setup

1. Install **GitHub** from the Status plugin store.
2. Create a configured app and enter owner and repository.
3. Grant network, keychain, OAuth, and background refresh permissions.
4. Choose **Connect account**, enter the displayed code on GitHub, then choose **Complete connection** in Status.
5. Run **Refresh repository activity** and **Refresh workflow runs**, then enable **Check workflow runs** if you want scheduled polling.
