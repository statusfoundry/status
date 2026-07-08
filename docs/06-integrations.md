# Integrations

Status should start with a small set of useful integrations, then grow through installable plugins.

## Integration categories

### Developer operations

- App Store Connect
- GitHub
- Jira
- Cloudflare
- Sentry
- Vercel
- Netlify
- Supabase
- Hetzner

### Content and channels

- YouTube
- RSS/feed
- Plausible/Fathom
- Google Analytics, later

### Business

- Stripe
- Paddle, later
- Lemon Squeezy, later

### Communication

- Gmail, later
- Slack
- Discord
- Email draft action

### Local/basic

- website uptime
- network check
- manual status
- generic webhook
- weather

## Bundled integrations

Bundled plugins should be universal and low-risk.

Recommended bundled set:

```txt
Website uptime
Network check
Manual status
RSS/feed
Generic webhook
Weather, optional
```

These make the app useful before a user installs anything.

## Store integrations

Installable plugins should be optional.

Recommended first store plugins:

```txt
App Store Connect
GitHub
Jira
YouTube
Cloudflare
Stripe
Sentry
Plausible/Fathom
```

## App Store Connect plugin

Purpose:

- show app list;
- show app review status;
- show latest version/build state;
- show waiting/in review/rejected/ready states;
- link directly to App Store Connect;
- emit events for review state changes.

Resources:

```txt
app
version
build
review_submission
review_message, later
```

Events:

```txt
app.review.rejected
app.review.in_review
app.review.waiting_for_review
app.version.ready_for_sale
app.build.processing_failed
```

Current implementation note: the bundled App Store Connect package uses `jwt-api-key` auth (`issuerId`, `keyId`, `.p8` private key) and asks for one `appId` during native setup. Manual refresh can list apps with JSON:API pagination; the scheduled review-state check uses the configured `appId` directly until the runtime supports chained per-resource requests.

Views:

- overview cards;
- app list;
- app detail;
- review timeline;
- needs attention panel.

Actions v1:

- open original;
- create local note;
- create Jira/GitHub issue through other plugins.

Avoid:

- submitting builds;
- editing metadata;
- replying automatically.

## GitHub plugin

Purpose:

- show repositories;
- show PRs needing review;
- show failing workflows;
- show recent issues;
- show blocked work;
- receive webhook events later.

Resources:

```txt
repository
pull_request
issue
workflow_run
release
```

Events:

```txt
github.pr.review_requested
github.pr.merged
github.workflow.failed
github.issue.assigned
github.release.published
```

Actions:

```txt
github.createIssue
github.commentOnIssue
github.openUrl
```

Avoid v1:

- merging PRs;
- closing issues;
- modifying branches.

## Jira plugin

Purpose:

- show assigned issues;
- show recently updated issues;
- show blocked issues;
- show project status;
- create follow-up issues from events.

Resources:

```txt
site
project
board
issue
sprint
```

Events:

```txt
jira.issue.assigned
jira.issue.updated
jira.issue.blocked
jira.issue.moved_to_review
jira.issue.overdue
```

Actions:

```txt
jira.createIssue
jira.addComment
```

Avoid v1:

- transitions;
- bulk edits;
- deleting issues.

## YouTube plugin

Purpose:

- connect multiple Google accounts/channels;
- show channels without switching accounts;
- show basic channel metrics;
- show latest uploads;
- warn about unusual drops.

Resources:

```txt
channel
video
metric_period
```

Events:

```txt
youtube.channel.views_dropped
youtube.channel.subscribers_changed
youtube.video.published
youtube.channel.no_upload_recently
```

Metrics:

```txt
views_7d
views_28d
subscribers_28d
watch_time_28d
latest_upload_age
```

Actions v1:

- open YouTube Studio;
- add to Status inbox;
- notify.

Avoid:

- uploading videos;
- changing metadata;
- posting comments.

## Cloudflare plugin

Purpose:

- show domains;
- show Workers;
- show Pages deployments;
- show R2 buckets;
- show failed deployments;
- show DNS/SSL attention items.

Resources:

```txt
account
zone
worker
pages_project
deployment
r2_bucket
```

Events:

```txt
cloudflare.deployment.failed
cloudflare.zone.ssl_issue
cloudflare.worker.error_rate_high
cloudflare.domain_expiring
```

Actions:

- open dashboard link;
- send notification;
- create issue via GitHub/Jira.

Avoid v1:

- editing DNS;
- deploying workers;
- deleting resources.

## Website uptime plugin

Purpose:

- monitor URLs;
- show current availability;
- emit events when down/recovered;
- record response time.

Resources:

```txt
website
endpoint
```

Events:

```txt
website.down
website.recovered
website.slow
```

Actions:

- notification;
- webhook;
- create issue through another plugin.

## Generic webhook plugin

Purpose:

- let any script/service emit events into Status;
- support custom payloads;
- support secret/token verification;
- bridge unsupported services.

### Local model before the relay

Until the relay exists (roadmap Phase 10), a local-only Mac has no public URL, so "generic webhook" in v1 means:

- a local HTTP listener on localhost, off by default and opt-in, for scripts and tools running on the same machine or LAN;
- manual payload import (paste or file) for testing mappings and rules.

Payloads still require the shared-secret/token check. True public inbound webhooks arrive with the relay and reuse the same payload shape, so nothing built against the local model changes later.

Event shape:

```json
{
  "type": "deploy.failed",
  "resource": "example.com",
  "title": "Deploy failed",
  "summary": "Production deployment failed.",
  "severity": "critical",
  "url": "https://github.com/..."
}
```

## Weather plugin

Weather is useful as a bundled example because it is generic and low-risk. It should not dominate the product.

Purpose:

- show current local weather;
- show severe weather notices if available;
- support simple status cards.

Avoid turning Status into a weather app.

## Integration priority

Recommended order:

1. Website uptime.
2. Generic webhook.
3. App Store Connect.
4. GitHub.
5. Jira.
6. YouTube.
7. Cloudflare.
8. Stripe.
9. Sentry.
10. Plausible/Fathom.

## Integration acceptance criteria

Each integration should have:

- setup flow;
- permissions screen;
- resource list;
- at least one event type;
- at least one useful status item;
- direct source links;
- error handling;
- audit output for actions;
- docs and example plugin manifest.

## Integration philosophy

An integration is successful when it saves a dashboard visit.

If a plugin only mirrors data without deciding what matters, it is not finished.
