# GitHub

Read-only GitHub repository events for workflow failures, pull requests, and issue activity.

## Why install this plugin

Install GitHub when you need a calm operational signal above your repositories — especially failing workflows and fresh pull request activity — without living inside the GitHub UI. Status normalizes repository state into events, inbox items, and native views so you can see what changed and open the provider when action is needed.

## What you configure

Create one configured app per repository you want to watch:

- **Owner** — GitHub user or organization name
- **Repository** — repository name

Status stores a GitHub fine-grained personal access token in Keychain when you complete auth setup. The plugin only calls declared `api.github.com` endpoints.

GitHub OAuth is not enabled in this package yet. GitHub's native-friendly device flow needs a separate Status auth flow, while GitHub OAuth App web flow requires a client secret and is not appropriate to store in a declarative plugin. For the current working app, use a read-only fine-grained token.

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
- `keychain` — store the GitHub token securely
- `background-refresh` — run scheduled workflow checks
- **Domains:** `api.github.com`

## What it does not do

- Does not replace the GitHub dashboard or Actions UI
- Does not merge pull requests, close issues, or modify branches
- Does not receive webhooks in the current package (polling only)

## Setup

1. Install **GitHub** from the Status plugin store.
2. Create a configured app and enter owner and repository.
3. Create a fine-grained GitHub personal access token for the repository with read-only metadata, actions, issues, and pull request access where available.
4. Add that token to the configured app in Status.
5. Grant network, keychain, and background refresh permissions.
6. Run **Refresh repository activity** and **Refresh workflow runs**, then enable **Check workflow runs** if you want scheduled polling.
