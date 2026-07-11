# YouTube

Read-only YouTube channel status for creator accounts, latest uploads, subscriber counts, and channel-level signals.

## Why install this plugin

Install YouTube when you manage creator channels and want a compact operational view of recent uploads, channel visibility, subscriber counts, and basic performance signals. Status is not trying to replace YouTube Studio; it gives you the quick "what changed and where do I click next" view.

## What you configure

Create one configured app per YouTube creator account or channel group you want to watch:

- **Google OAuth client ID** - the public OAuth client id for a Google Cloud OAuth app that uses `status://oauth/youtube` as an allowed redirect URI

Auth uses Google OAuth 2 with PKCE. Status owns authorization, token refresh, and Keychain-backed token storage. The plugin reads channel and upload data through declared YouTube Data API hosts only.

## What it exposes

### Resources

- **channel** - creator channel records with title, visibility, subscriber count, and upload playlist context
- **video** - recent uploads with title, publish time, thumbnail, and direct YouTube links

### Events

| Event | Meaning | Default notification |
| --- | --- | --- |
| `youtube.video.published` | A video appeared in the connected creator account's recent uploads | Digest |
| `youtube.channel.visibility_limited` | A connected YouTube channel is not currently public | Dashboard only |

### Views

- **Channels** - channel list with visibility and subscriber summary
- **Recent uploads** - timeline of recently published videos
- **Creator metrics** - compact metric grid for subscriber and upload counts

### Checks

- **Refresh channel stats** - manual refresh of channel visibility and metrics
- **Refresh recent uploads** - manual refresh of recent uploads
- **Check YouTube channels** - cron schedule for channel and visibility polling

## Suggested automations

Suggested rules install disabled. Enable presets if you want limited channel visibility or fresh uploads to appear in the Status inbox or digest.

## Actions

Read-only in v1. Status does not publish, edit, delete, schedule, monetize, or moderate YouTube content.

## Permissions and domains

- `network` - call Google OAuth and YouTube Data HTTPS APIs
- `keychain` - store OAuth token references securely
- `oauth` - connect the configured creator account through Google OAuth 2 with PKCE
- `background-refresh` - run scheduled channel checks
- **Domains:** `accounts.google.com`, `oauth2.googleapis.com`, `www.googleapis.com`

## What it does not do

- Does not replace YouTube Studio analytics, comments, copyright, or monetization tools
- Does not publish videos or edit channel metadata
- Does not moderate comments or manage community settings
- Does not request undeclared Google API hosts

## Setup

1. Install **YouTube** from the Status plugin store.
2. In Google Cloud, create an OAuth client for YouTube Data API access with `status://oauth/youtube` as an allowed redirect URI.
3. Create a configured app in Status and paste the Google OAuth client ID.
4. Grant network, keychain, OAuth, and background refresh permissions.
5. Connect with Google OAuth using the creator account you want to watch.
6. Run **Refresh channel stats** and **Refresh recent uploads**, then enable **Check YouTube channels** if you want scheduled polling.
