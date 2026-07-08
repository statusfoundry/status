import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { route } from "./index.js";

async function get(path) {
  return route(new Request(`https://status-registry.hakobs.com${path}`));
}

test("health endpoint responds", async () => {
  const response = await get("/health");
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.service, "status-registry");
  assert.equal(body.ok, true);
});

test("plugin list returns installable summaries", async () => {
  const response = await get("/v1/plugins?platform=macOS&coreVersion=0.1.0");
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.ok(body.plugins.length >= 3);
  assert.equal(body.plugins[0].versions, undefined);
  assert.ok(body.plugins.every((plugin) => plugin.trustLevel === "official"));
});

test("plugin detail and versions endpoints return package metadata", async () => {
  const detail = await get("/v1/plugins/com.status.github");
  const detailBody = await detail.json();
  const versions = await get("/v1/plugins/com.status.github/versions");
  const versionsBody = await versions.json();
  const version = await get("/v1/plugins/com.status.github/versions/0.1.0");
  const versionBody = await version.json();

  assert.equal(detail.status, 200);
  assert.equal(detailBody.id, "com.status.github");
  assert.equal(detailBody.versions.length, 1);
  assert.equal(versions.status, 200);
  assert.equal(versionsBody.pluginId, "com.status.github");
  assert.equal(versionsBody.versions[0].version, "0.1.0");
  assert.equal(version.status, 200);
  assert.equal(versionBody.pluginId, "com.status.github");
  assert.match(versionBody.packageUrl, /com\.status\.github-0\.1\.0\.statusplugin\.zip$/);
  assert.match(versionBody.signature, /^[A-Za-z0-9+/]+={0,2}$/);
});

test("plugin package and manifest artifacts are downloadable and match registry hash", async () => {
  const version = await get("/v1/plugins/com.status.github/versions/0.1.0");
  const versionBody = await version.json();
  const packageURL = new URL(versionBody.packageUrl);
  const manifestURL = new URL(versionBody.manifestUrl);
  const packageResponse = await get(packageURL.pathname);
  const manifestResponse = await get(manifestURL.pathname);
  const packageData = Buffer.from(await packageResponse.arrayBuffer());
  const manifest = await manifestResponse.json();

  assert.equal(packageResponse.status, 200);
  assert.equal(packageResponse.headers.get("content-type"), "application/zip");
  assert.equal(createHash("sha256").update(packageData).digest("hex"), versionBody.sha256);
  assert.equal(manifestResponse.status, 200);
  assert.equal(manifest.id, "com.status.github");
  assert.equal(manifest.version, "0.1.0");
});

test("plugin artifacts prefer R2 bucket when available", async () => {
  const response = await route(
    new Request("https://status-registry.hakobs.com/plugins/com.status.github/0.1.0/manifest.json"),
    {
      PLUGIN_BUCKET: {
        async get(key) {
          assert.equal(key, "plugins/com.status.github/0.1.0/manifest.json");
          return {
            body: Buffer.from("{\"id\":\"from-r2\"}"),
            httpMetadata: {
              contentType: "application/json; charset=utf-8"
            }
          };
        }
      }
    }
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "application/json; charset=utf-8");
  assert.equal(body.id, "from-r2");
});

test("compatibility filters remove unsupported versions", async () => {
  const response = await get("/v1/plugins?platform=watchOS&coreVersion=0.1.0");
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.deepEqual(body.plugins, []);
});

test("unknown routes return structured 404", async () => {
  const response = await get("/v1/plugins/com.status.missing");
  const body = await response.json();

  assert.equal(response.status, 404);
  assert.equal(body.error, "not_found");
});
