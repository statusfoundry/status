# Mock Operations Plugin

Starter template for third-party Status plugin authors.

## Use this template

Copy this folder, rename it, and replace the example provider with your HTTPS API plus recorded fixtures.

- In the Status monorepo: `plugins/examples/mock-operations`
- Website guide: `/developers/` and `/docs/plugin-author-guide/`
- Planned standalone repo: `status-plugin-example` (fork-friendly mirror of this folder)

## Validate

From the repository root:

```sh
npm run plugins:validate-local -- plugins/examples/mock-operations
```

This validates schemas, cross-file references, and prints the package SHA-256. The package stays in `local-dev` trust territory and is not published to the registry.

## What it demonstrates

- declared network permissions and domains;
- native setup fields;
- request definitions for read and review-required write flows;
- resource, event, and metric mappings;
- manual and cron triggers;
- suggested rules that install disabled;
- app-owned view descriptors;
- review-required action declarations.

`fixtures/fetch_status.json` is the recorded response shape used by native mapping tests and Developer Mode fixture preview. Replace the example.com endpoints with a real HTTPS API when adapting this template.

## Test in the app

1. Build and open StatusMac.
2. Enable Developer Mode.
3. Use **Install Local** and select this folder.
4. Configure the plugin and run a manual trigger.
5. Use **Preview Fixture** to inspect mapped output without writing to SQLite.

## Submit for review

v1 has no public upload form. Open a pull request with fixtures and validation evidence. Status reviews, signs, and publishes approved packages.