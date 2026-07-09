export const registry = {
  "schemaVersion": "1.0.0",
  "plugins": [
    {
      "id": "com.status.appstoreconnect",
      "name": "App Store Connect",
      "summary": "Track app review, builds, and release status.",
      "description": "Read-only App Store Connect status events for apps, review state, build processing, and release readiness.",
      "category": "developer",
      "author": "Status Foundry",
      "trustLevel": "official",
      "permissions": [
        "network",
        "keychain",
        "private-key",
        "background-refresh"
      ],
      "domains": [
        "api.appstoreconnect.apple.com"
      ],
      "versions": [
        {
          "version": "0.1.0",
          "minCoreVersion": "0.1.0",
          "platforms": [
            "macOS",
            "iOS"
          ],
          "packageUrl": "https://status-registry.hakobs.com/plugins/com.status.appstoreconnect/0.1.0/com.status.appstoreconnect-0.1.0.statusplugin.zip",
          "manifestUrl": "https://status-registry.hakobs.com/plugins/com.status.appstoreconnect/0.1.0/manifest.json",
          "sha256": "f073deda441a714eaea42c3165ae763b97869849c8b65ce0c5e6e56a5fb0ab9f",
          "signature": "TqpVY83St+nj6Qz8VARvTJycNudtySO35nErAJSQhp+ToneyFzTPPzYiLFKFOKAcpPaszDlZre+BNZvnRYq/Dw==",
          "signedBy": "status-foundry-dev",
          "releasedAt": "2026-07-07T12:00:00Z"
        }
      ]
    },
    {
      "id": "com.status.github",
      "name": "GitHub",
      "summary": "Track workflow failures, pull requests, and issue activity.",
      "description": "Read-only GitHub repository events for workflow failures, pull requests, and issue activity.",
      "category": "developer",
      "author": "Status Foundry",
      "trustLevel": "official",
      "permissions": [
        "network",
        "keychain",
        "background-refresh"
      ],
      "domains": [
        "api.github.com"
      ],
      "versions": [
        {
          "version": "0.1.0",
          "minCoreVersion": "0.1.0",
          "platforms": [
            "macOS",
            "iOS"
          ],
          "packageUrl": "https://status-registry.hakobs.com/plugins/com.status.github/0.1.0/com.status.github-0.1.0.statusplugin.zip",
          "manifestUrl": "https://status-registry.hakobs.com/plugins/com.status.github/0.1.0/manifest.json",
          "sha256": "47a057c490bcd941da44a68f25a91e2af1901212a072db6b8346cd1f6a398692",
          "signature": "gzTVdjL8HleZMshqlM1EqfRmpLzn3xUGTdQANhEDNeg5gdb0csfZjnJMvQD5bGkzegC0eaG71RBl9xICV868CA==",
          "signedBy": "status-foundry-dev",
          "releasedAt": "2026-07-07T12:00:00Z"
        }
      ]
    },
    {
      "id": "com.status.website",
      "name": "Website Uptime",
      "summary": "Track website health and response status.",
      "description": "Declarative uptime checks for sites and endpoints the user chooses to track.",
      "category": "monitoring",
      "author": "Status Foundry",
      "trustLevel": "official",
      "permissions": [
        "network",
        "user-configured-domains",
        "background-refresh"
      ],
      "domains": [],
      "versions": [
        {
          "version": "0.1.0",
          "minCoreVersion": "0.1.0",
          "platforms": [
            "macOS",
            "iOS"
          ],
          "packageUrl": "https://status-registry.hakobs.com/plugins/com.status.website/0.1.0/com.status.website-0.1.0.statusplugin.zip",
          "manifestUrl": "https://status-registry.hakobs.com/plugins/com.status.website/0.1.0/manifest.json",
          "sha256": "db66ba5d7ca1e96a1af4055ea2c8c6778a0f0897c387bd6cf05686a609f6005a",
          "signature": "kOFPIddeIzD5qolFxdQwxd3tss5QyugQ6gtQGXfYxdoOokDbQEeuZyd7v5dDIPG1spiJgGQ50x9uu6Gub5G3Aw==",
          "signedBy": "status-foundry-dev",
          "releasedAt": "2026-07-07T12:00:00Z"
        }
      ]
    }
  ]
};


export const revocations = {
  "schemaVersion": "1.0.0",
  "revokedPlugins": [],
  "revokedVersions": [],
  "revokedHashes": [],
  "revokedSigningKeys": []
};
