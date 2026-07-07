export const registry = {
  schemaVersion: "1.0.0",
  plugins: [
    {
      id: "com.status.appstoreconnect",
      name: "App Store Connect",
      summary: "Track app review, builds, and release status.",
      description: "Read-only App Store Connect status events for apps, review state, build processing, and release readiness.",
      category: "developer",
      author: "Status Foundry",
      trustLevel: "official",
      permissions: ["network"],
      domains: ["api.appstoreconnect.apple.com"],
      versions: [
        {
          version: "0.1.0",
          minCoreVersion: "0.1.0",
          platforms: ["macOS", "iOS"],
          packageUrl: "https://status-registry.hakobs.com/plugins/com.status.appstoreconnect/0.1.0/com.status.appstoreconnect-0.1.0.statusplugin.zip",
          manifestUrl: "https://status-registry.hakobs.com/plugins/com.status.appstoreconnect/0.1.0/manifest.json",
          sha256: "b6a9d31fb02f91c6a384d9960f3b35f4b54a2f838f4d7a4e6a4a0d96fca94232",
          signature: null,
          signedBy: "status-foundry-dev",
          releasedAt: "2026-07-07T12:00:00Z"
        }
      ]
    },
    {
      id: "com.status.github",
      name: "GitHub",
      summary: "Track workflow failures, pull requests, and issue activity.",
      description: "Read-only GitHub repository events with future reviewed write actions for issue creation.",
      category: "developer",
      author: "Status Foundry",
      trustLevel: "official",
      permissions: ["network"],
      domains: ["api.github.com"],
      versions: [
        {
          version: "0.1.0",
          minCoreVersion: "0.1.0",
          platforms: ["macOS", "iOS"],
          packageUrl: "https://status-registry.hakobs.com/plugins/com.status.github/0.1.0/com.status.github-0.1.0.statusplugin.zip",
          manifestUrl: "https://status-registry.hakobs.com/plugins/com.status.github/0.1.0/manifest.json",
          sha256: "dcd4260b527a28d62ad2a956b00c4f5616416b2fdc0506e6fe5f6b616f5df5aa",
          signature: null,
          signedBy: "status-foundry-dev",
          releasedAt: "2026-07-07T12:00:00Z"
        }
      ]
    },
    {
      id: "com.status.website",
      name: "Website Uptime",
      summary: "Track website health and response status.",
      description: "Declarative uptime checks for sites and endpoints the user chooses to track.",
      category: "monitoring",
      author: "Status Foundry",
      trustLevel: "official",
      permissions: ["network"],
      domains: [],
      versions: [
        {
          version: "0.1.0",
          minCoreVersion: "0.1.0",
          platforms: ["macOS", "iOS"],
          packageUrl: "https://status-registry.hakobs.com/plugins/com.status.website/0.1.0/com.status.website-0.1.0.statusplugin.zip",
          manifestUrl: "https://status-registry.hakobs.com/plugins/com.status.website/0.1.0/manifest.json",
          sha256: "c9ca60fa6c38bb6f38fc097a080ef0a993cc67f198af86b7fb9e21f87c8fcb09",
          signature: null,
          signedBy: "status-foundry-dev",
          releasedAt: "2026-07-07T12:00:00Z"
        }
      ]
    }
  ]
};

export const revocations = {
  schemaVersion: "1.0.0",
  revokedPlugins: [],
  revokedVersions: [],
  revokedHashes: [],
  revokedSigningKeys: []
};
