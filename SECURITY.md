# Security

Status handles credentials, operational events, plugin packages, and automation actions. Security issues should be reported privately.

## Reporting

Email security reports to `security@hakobs.com`.

Include:

- affected component;
- reproduction steps;
- impact;
- any relevant logs or package metadata.

Do not open a public issue for vulnerabilities involving credentials, package trust, registry integrity, or action execution.

## Current security model

- Secrets are stored through Keychain references, not plain SQLite columns.
- v1 plugins are declarative adapters, not executable code.
- Registry plugins require local package hash verification, signature material, and revocation checks before install.
- Public third-party plugin publishing is review-based.
- Full cryptographic package signature verification is still planned before public distribution.
- Destructive actions are outside v1 scope.

See `docs/07-security-privacy.md` for the full model.
