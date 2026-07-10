# Contributing

Status is documentation-first. Product doctrine and the canonical spec decide implementation direction.

## Before changing code

Read, in order:

1. `AGENTS.md`
2. `DOCTRINE.md`
3. `SPEC.md`
4. Relevant docs under `docs/`

For plugin changes, also read `docs/04-plugin-system.md`, `docs/16-mapping-language.md`, and `schemas/plugin/v1/`.

## Local setup

```sh
npm ci
npm run plugins:build
npm run check
swift test
xcodegen generate
xcodebuild -project Status.xcodeproj -scheme StatusMac -destination 'platform=macOS' -derivedDataPath /tmp/status-mac-derived build
xcodebuild -project Status.xcodeproj -scheme StatusiOS -destination 'generic/platform=iOS' -derivedDataPath /tmp/status-ios-derived CODE_SIGNING_ALLOWED=NO build
```

`Status.xcodeproj` is generated and intentionally ignored.

## Commit style

Use Conventional Commits:

- `feat:` for product features
- `fix:` for bugs
- `docs:` for documentation
- `test:` for tests
- `ci:` for CI or deployment workflows
- `build:` for package/build configuration
- `chore:` for repository maintenance
- `refactor:` for internal restructuring without behavior changes

## Plugin contributions

Public plugin upload is not supported in v1. Third-party plugins use pull request review.

Read `docs/22-plugin-governance.md` before proposing a new plugin or changing registry publication rules.

Plugin submissions must:

- be declarative data only;
- declare all domains and permissions;
- avoid arbitrary executable code;
- avoid plugin-owned UI;
- include a complete `README.md` based on `plugins/README.template.md`;
- include fixtures where mappings are added;
- pass `npm run plugins:build` and `npm run check`;
- be reviewed before they are signed or published.

Status signs packages that appear in the hosted registry. Do not commit production signing keys.
