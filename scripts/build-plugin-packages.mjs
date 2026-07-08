import { createHash } from "node:crypto";
import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const pluginsRoot = path.join(root, "plugins", "bundled");
const registryDataPath = path.join(root, "workers", "registry", "src", "registry-data.js");
const artifactsPath = path.join(root, "workers", "registry", "src", "plugin-artifacts.js");
const webRegistryPath = path.join(root, "web", "src", "generated", "registry.json");
const packageDistRoot = path.join(root, "workers", "registry", "dist", "plugins");
const registryBaseURL = "https://status-registry.hakobs.com";
const checkOnly = process.argv.includes("--check");

const allowedPlatforms = new Set(["macOS", "iOS"]);
const allowedPermissions = new Set([
  "network",
  "keychain",
  "oauth",
  "api-key",
  "private-key",
  "background-refresh",
  "push-webhook",
  "user-configured-domains",
  "write-actions",
  "local-notification-suggestion"
]);

const crcTable = new Uint32Array(256);
for (let index = 0; index < crcTable.length; index += 1) {
  let value = index;
  for (let bit = 0; bit < 8; bit += 1) {
    value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
  }
  crcTable[index] = value >>> 0;
}

const encoder = new TextEncoder();

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function u16(value) {
  const buffer = Buffer.alloc(2);
  buffer.writeUInt16LE(value);
  return buffer;
}

function u32(value) {
  const buffer = Buffer.alloc(4);
  buffer.writeUInt32LE(value >>> 0);
  return buffer;
}

function deterministicZip(files) {
  const localParts = [];
  const centralParts = [];
  let offset = 0;

  for (const file of files) {
    const name = Buffer.from(file.name, "utf8");
    const data = Buffer.from(file.data);
    const checksum = crc32(data);
    const localHeader = Buffer.concat([
      u32(0x04034b50),
      u16(20),
      u16(0),
      u16(0),
      u16(0),
      u16(0),
      u32(checksum),
      u32(data.length),
      u32(data.length),
      u16(name.length),
      u16(0),
      name
    ]);
    const centralHeader = Buffer.concat([
      u32(0x02014b50),
      u16(20),
      u16(20),
      u16(0),
      u16(0),
      u16(0),
      u16(0),
      u32(checksum),
      u32(data.length),
      u32(data.length),
      u16(name.length),
      u16(0),
      u16(0),
      u16(0),
      u16(0),
      u32(0),
      u32(offset),
      name
    ]);

    localParts.push(localHeader, data);
    centralParts.push(centralHeader);
    offset += localHeader.length + data.length;
  }

  const centralDirectory = Buffer.concat(centralParts);
  const end = Buffer.concat([
    u32(0x06054b50),
    u16(0),
    u16(0),
    u16(files.length),
    u16(files.length),
    u32(centralDirectory.length),
    u32(offset),
    u16(0)
  ]);

  return Buffer.concat([...localParts, centralDirectory, end]);
}

async function readJSON(filePath) {
  return JSON.parse(await readFile(filePath, "utf8"));
}

async function readOptionalJSON(filePath) {
  try {
    return await readJSON(filePath);
  } catch (error) {
    if (error?.code === "ENOENT") {
      return undefined;
    }
    throw error;
  }
}

function fail(message) {
  throw new Error(message);
}

function validateManifest(manifest, sourceName) {
  for (const field of ["id", "name", "version", "author", "category", "description", "minCoreVersion"]) {
    if (typeof manifest[field] !== "string" || manifest[field].trim() === "") {
      fail(`${sourceName}: manifest.${field} is required`);
    }
  }
  if (/^[a-z0-9]+(\.[a-z0-9][a-z0-9-]*)+$/.test(manifest.id) === false) {
    fail(`${sourceName}: manifest.id must be reverse-DNS style`);
  }
  if (/^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/.test(manifest.version) === false) {
    fail(`${sourceName}: manifest.version must be semver`);
  }
  if (/^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/.test(manifest.minCoreVersion) === false) {
    fail(`${sourceName}: manifest.minCoreVersion must be semver`);
  }
  if (!Array.isArray(manifest.platforms) || manifest.platforms.length === 0) {
    fail(`${sourceName}: manifest.platforms must not be empty`);
  }
  for (const platform of manifest.platforms) {
    if (allowedPlatforms.has(platform) === false) {
      fail(`${sourceName}: unsupported platform ${platform}`);
    }
  }
  if (!Array.isArray(manifest.permissions)) {
    fail(`${sourceName}: manifest.permissions must be an array`);
  }
  for (const permission of manifest.permissions) {
    if (allowedPermissions.has(permission) === false) {
      fail(`${sourceName}: unsupported permission ${permission}`);
    }
  }
  if (!Array.isArray(manifest.domains)) {
    fail(`${sourceName}: manifest.domains must be an array`);
  }
  if (
    manifest.permissions.includes("network") &&
    manifest.permissions.includes("user-configured-domains") === false &&
    manifest.domains.length === 0
  ) {
    fail(`${sourceName}: network plugins must declare domains`);
  }
  for (const domain of manifest.domains) {
    if (/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/.test(domain) === false) {
      fail(`${sourceName}: invalid domain ${domain}`);
    }
  }
  if (manifest.permissions.includes("oauth")) {
    fail(`${sourceName}: OAuth plugins are deferred past v1`);
  }
}

function validateRequestDefinitions(manifest, requestsFile, sourceName) {
  if (!requestsFile) {
    return new Set();
  }
  if (!requestsFile.requests || typeof requestsFile.requests !== "object" || Array.isArray(requestsFile.requests)) {
    fail(`${sourceName}: requests.json must contain a requests object`);
  }

  const requestIDs = new Set(Object.keys(requestsFile.requests));
  const declaredDomains = new Set(manifest.domains.map((domain) => domain.toLowerCase()));
  const usesUserConfiguredDomains = manifest.permissions.includes("user-configured-domains");

  for (const [requestID, request] of Object.entries(requestsFile.requests)) {
    if (/^[a-z][a-z0-9_]*$/.test(requestID) === false) {
      fail(`${sourceName}: invalid request id ${requestID}`);
    }
    if (!request || typeof request !== "object") {
      fail(`${sourceName}: request ${requestID} must be an object`);
    }
    if (typeof request.url !== "string" || request.url.trim() === "") {
      fail(`${sourceName}: request ${requestID} must define a url`);
    }
    let url;
    try {
      url = new URL(request.url);
    } catch {
      if (request.url.startsWith("https://{{") && usesUserConfiguredDomains) {
        continue;
      }
      fail(`${sourceName}: request ${requestID} has invalid url ${request.url}`);
    }
    if (url.hostname.includes("{{")) {
      if (usesUserConfiguredDomains === false) {
        fail(`${sourceName}: request ${requestID} uses a templated host without user-configured-domains`);
      }
      continue;
    }
    if (url.protocol !== "https:") {
      fail(`${sourceName}: request ${requestID} must use https`);
    }
    if (usesUserConfiguredDomains === false && declaredDomains.has(url.hostname.toLowerCase()) === false) {
      fail(`${sourceName}: request ${requestID} uses undeclared domain ${url.hostname}`);
    }
  }

  return requestIDs;
}

function validateTriggers(triggersFile, requestIDs, sourceName) {
  if (!triggersFile) {
    return;
  }
  if (!Array.isArray(triggersFile.triggers) || triggersFile.triggers.length === 0) {
    fail(`${sourceName}: triggers.json must contain triggers`);
  }
  for (const trigger of triggersFile.triggers) {
    if (!trigger?.id || !trigger?.type || !trigger?.label) {
      fail(`${sourceName}: every trigger needs id, type, and label`);
    }
    if (trigger.request && requestIDs.has(trigger.request) === false) {
      fail(`${sourceName}: trigger ${trigger.id} references missing request ${trigger.request}`);
    }
  }
}

function validateEvents(eventsFile, sourceName) {
  if (!eventsFile) {
    return new Set();
  }
  if (!Array.isArray(eventsFile.events) || eventsFile.events.length === 0) {
    fail(`${sourceName}: events.json must contain events`);
  }
  const eventTypes = new Set();
  for (const event of eventsFile.events) {
    if (typeof event.type !== "string" || /^[a-z0-9_]+(\.[a-z0-9_]+)+$/.test(event.type) === false) {
      fail(`${sourceName}: invalid event type ${event.type}`);
    }
    eventTypes.add(event.type);
  }
  return eventTypes;
}

function validateMappings(mappingsFile, requestIDs, eventTypes, sourceName) {
  if (!mappingsFile) {
    return;
  }
  for (const resource of mappingsFile.resources ?? []) {
    if (resource.request && requestIDs.has(resource.request) === false) {
      fail(`${sourceName}: resource mapping references missing request ${resource.request}`);
    }
  }
  for (const event of mappingsFile.events ?? []) {
    if (eventTypes.has(event.type) === false) {
      fail(`${sourceName}: mapping references undeclared event ${event.type}`);
    }
    if (event.request && requestIDs.has(event.request) === false) {
      fail(`${sourceName}: event mapping ${event.type} references missing request ${event.request}`);
    }
  }
  for (const metric of mappingsFile.metrics ?? []) {
    if (metric.request && requestIDs.has(metric.request) === false) {
      fail(`${sourceName}: metric mapping ${metric.name ?? "(unnamed)"} references missing request ${metric.request}`);
    }
  }
}

function validateRulePresets(presetsFile, eventTypes, sourceName) {
  if (!presetsFile) {
    return;
  }
  if (!Array.isArray(presetsFile.presets) || presetsFile.presets.length === 0) {
    fail(`${sourceName}: rules.presets.json must contain presets`);
  }
  for (const preset of presetsFile.presets) {
    const eventType = preset?.when?.eventType;
    if (eventTypes.has(eventType) === false) {
      fail(`${sourceName}: rule preset ${preset?.name ?? "(unnamed)"} references undeclared event ${eventType}`);
    }
    if (!Array.isArray(preset.then) || preset.then.length === 0) {
      fail(`${sourceName}: rule preset ${preset?.name ?? "(unnamed)"} must define actions`);
    }
  }
}

async function validatePluginPackage(pluginDirectory, manifest, sourceName) {
  const requestsFile = await readOptionalJSON(path.join(pluginDirectory, "requests.json"));
  const triggersFile = await readOptionalJSON(path.join(pluginDirectory, "triggers.json"));
  const eventsFile = await readOptionalJSON(path.join(pluginDirectory, "events.json"));
  const mappingsFile = await readOptionalJSON(path.join(pluginDirectory, "mappings.json"));
  const presetsFile = await readOptionalJSON(path.join(pluginDirectory, "rules.presets.json"));

  const requestIDs = validateRequestDefinitions(manifest, requestsFile, sourceName);
  const eventTypes = validateEvents(eventsFile, sourceName);
  validateTriggers(triggersFile, requestIDs, sourceName);
  validateMappings(mappingsFile, requestIDs, eventTypes, sourceName);
  validateRulePresets(presetsFile, eventTypes, sourceName);
}

async function pluginFiles(pluginDirectory) {
  const names = (await readdir(pluginDirectory)).filter((name) => name.endsWith(".json")).sort();
  return Promise.all(names.map(async (name) => ({
    name,
    data: await readFile(path.join(pluginDirectory, name))
  })));
}

function jsModule(name, value) {
  return `export const ${name} = ${JSON.stringify(value, null, 2)};\n`;
}

async function build() {
  const pluginDirectoryNames = (await readdir(pluginsRoot, { withFileTypes: true }))
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();

  const plugins = [];
  const artifacts = {};

  for (const directoryName of pluginDirectoryNames) {
    const pluginDirectory = path.join(pluginsRoot, directoryName);
    const manifest = await readJSON(path.join(pluginDirectory, "manifest.json"));
    const metadata = await readJSON(path.join(pluginDirectory, "registry.json"));
    validateManifest(manifest, directoryName);
    await validatePluginPackage(pluginDirectory, manifest, directoryName);

    const files = await pluginFiles(pluginDirectory);
    const packageData = deterministicZip(files);
    const sha256 = createHash("sha256").update(packageData).digest("hex");
    const packagePath = `/plugins/${manifest.id}/${manifest.version}/${manifest.id}-${manifest.version}.statusplugin.zip`;
    const manifestPath = `/plugins/${manifest.id}/${manifest.version}/manifest.json`;
    const signature = `dev-signature:${sha256}`;

    artifacts[packagePath] = {
      contentType: "application/zip",
      bodyBase64: packageData.toString("base64")
    };
    artifacts[manifestPath] = {
      contentType: "application/json; charset=utf-8",
      bodyBase64: Buffer.from(JSON.stringify(manifest, null, 2) + "\n").toString("base64")
    };

    plugins.push({
      id: manifest.id,
      name: manifest.name,
      summary: metadata.summary,
      description: manifest.description,
      category: manifest.category,
      author: manifest.author,
      trustLevel: metadata.trustLevel,
      permissions: manifest.permissions,
      domains: manifest.domains,
      versions: [
        {
          version: manifest.version,
          minCoreVersion: manifest.minCoreVersion,
          platforms: manifest.platforms,
          packageUrl: `${registryBaseURL}${packagePath}`,
          manifestUrl: `${registryBaseURL}${manifestPath}`,
          sha256,
          signature,
          signedBy: metadata.signedBy,
          releasedAt: metadata.releasedAt
        }
      ]
    });

    const distDirectory = path.join(packageDistRoot, manifest.id, manifest.version);
    if (!checkOnly) {
      await mkdir(distDirectory, { recursive: true });
      await writeFile(path.join(distDirectory, `${manifest.id}-${manifest.version}.statusplugin.zip`), packageData);
      await writeFile(path.join(distDirectory, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
    }
  }

  const registryModule = `${jsModule("registry", { schemaVersion: "1.0.0", plugins })}
\n${jsModule("revocations", {
    schemaVersion: "1.0.0",
    revokedPlugins: [],
    revokedVersions: [],
    revokedHashes: [],
    revokedSigningKeys: []
  })}`;
  const artifactModule = jsModule("pluginArtifacts", artifacts);
  const webRegistryJSON = JSON.stringify({ schemaVersion: "1.0.0", plugins }, null, 2) + "\n";

  if (checkOnly) {
    const [currentRegistry, currentArtifacts, currentWebRegistry] = await Promise.all([
      readFile(registryDataPath, "utf8"),
      readFile(artifactsPath, "utf8"),
      readFile(webRegistryPath, "utf8")
    ]);
    if (currentRegistry !== registryModule) {
      fail("workers/registry/src/registry-data.js is out of date. Run npm run plugins:build.");
    }
    if (currentArtifacts !== artifactModule) {
      fail("workers/registry/src/plugin-artifacts.js is out of date. Run npm run plugins:build.");
    }
    if (currentWebRegistry !== webRegistryJSON) {
      fail("web/src/generated/registry.json is out of date. Run npm run plugins:build.");
    }
  } else {
    await mkdir(path.dirname(webRegistryPath), { recursive: true });
    await writeFile(registryDataPath, registryModule);
    await writeFile(artifactsPath, artifactModule);
    await writeFile(webRegistryPath, webRegistryJSON);
  }

  console.log(`${checkOnly ? "Checked" : "Built"} ${plugins.length} plugin package(s).`);
}

await build();
