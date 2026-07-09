import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

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
const allowedViewTypes = new Set([
  "overview_cards",
  "resource_list",
  "resource_detail",
  "timeline",
  "metric_grid",
  "alert_list"
]);

const crcTable = new Uint32Array(256);
for (let index = 0; index < crcTable.length; index += 1) {
  let value = index;
  for (let bit = 0; bit < 8; bit += 1) {
    value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
  }
  crcTable[index] = value >>> 0;
}

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

export function deterministicZip(files) {
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

export function fail(message) {
  throw new Error(message);
}

export function validateManifest(manifest, sourceName) {
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
  if (manifest.icon !== undefined && (typeof manifest.icon !== "string" || manifest.icon.trim() === "")) {
    fail(`${sourceName}: manifest.icon must be a non-empty SF Symbol name or sf: prefixed name`);
  }
  if (manifest.accentColor !== undefined && /^#[0-9A-Fa-f]{6}$/.test(manifest.accentColor) === false) {
    fail(`${sourceName}: manifest.accentColor must be a #RRGGBB hex color`);
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
    if (usesUserConfiguredDomains === false && manifest.domains.map((domain) => domain.toLowerCase()).includes(url.hostname.toLowerCase()) === false) {
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
    if (typeof event.label !== "string" || event.label.trim() === "") {
      fail(`${sourceName}: event ${event.type} needs label`);
    }
    eventTypes.add(event.type);
  }
  return eventTypes;
}

function validateMappings(mappingsFile, requestIDs, eventTypes, sourceName) {
  const resourceTypes = new Set();
  if (!mappingsFile) {
    return resourceTypes;
  }
  for (const resource of mappingsFile.resources ?? []) {
    if (resource.request && requestIDs.has(resource.request) === false) {
      fail(`${sourceName}: resource mapping references missing request ${resource.request}`);
    }
    if (typeof resource.type !== "string" || /^[a-z][a-z0-9_]*$/.test(resource.type) === false) {
      fail(`${sourceName}: resource mapping has invalid type ${resource.type}`);
    }
    resourceTypes.add(resource.type);
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
  return resourceTypes;
}

function validateViews(viewsFile, resourceTypes, sourceName) {
  if (!viewsFile) {
    return;
  }
  if (!Array.isArray(viewsFile.views) || viewsFile.views.length === 0) {
    fail(`${sourceName}: views.json must contain views`);
  }

  const ids = new Set();
  for (const view of viewsFile.views) {
    if (!view || typeof view !== "object") {
      fail(`${sourceName}: every view must be an object`);
    }
    if (typeof view.id !== "string" || /^[a-z][a-z0-9_-]*$/.test(view.id) === false) {
      fail(`${sourceName}: view has invalid id ${view.id}`);
    }
    if (ids.has(view.id)) {
      fail(`${sourceName}: duplicate view id ${view.id}`);
    }
    ids.add(view.id);

    if (allowedViewTypes.has(view.type) === false) {
      fail(`${sourceName}: view ${view.id} has unsupported type ${view.type}`);
    }
    if (["resource_list", "resource_detail"].includes(view.type) && !view.resourceType) {
      fail(`${sourceName}: view ${view.id} requires resourceType`);
    }
    if (view.resourceType) {
      if (typeof view.resourceType !== "string" || /^[a-z][a-z0-9_]*$/.test(view.resourceType) === false) {
        fail(`${sourceName}: view ${view.id} has invalid resourceType ${view.resourceType}`);
      }
      if (resourceTypes.has(view.resourceType) === false) {
        fail(`${sourceName}: view ${view.id} references undeclared resource type ${view.resourceType}`);
      }
    }
    if (view.fields !== undefined) {
      if (!Array.isArray(view.fields) || view.fields.length === 0) {
        fail(`${sourceName}: view ${view.id} fields must be a non-empty array`);
      }
      const fields = new Set();
      for (const field of view.fields) {
        if (typeof field !== "string" || field.trim() === "") {
          fail(`${sourceName}: view ${view.id} has invalid field`);
        }
        if (fields.has(field)) {
          fail(`${sourceName}: view ${view.id} has duplicate field ${field}`);
        }
        fields.add(field);
      }
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
    for (const action of preset.then) {
      if (!action || typeof action !== "object" || typeof action.action !== "string") {
        fail(`${sourceName}: rule preset ${preset?.name ?? "(unnamed)"} has invalid action`);
      }
      if (action.parameters !== undefined) {
        fail(`${sourceName}: rule preset ${preset?.name ?? "(unnamed)"} action parameters must be top-level fields`);
      }
    }
  }
}

function validateActions(actionsFile, requestIDs, manifest, sourceName) {
  if (!actionsFile) {
    return;
  }
  if (!Array.isArray(actionsFile.actions) || actionsFile.actions.length === 0) {
    fail(`${sourceName}: actions.json must contain actions`);
  }
  const actionIDs = new Set();
  for (const action of actionsFile.actions) {
    if (typeof action.id !== "string" || /^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)*$/.test(action.id) === false) {
      fail(`${sourceName}: action has invalid id ${action.id}`);
    }
    if (actionIDs.has(action.id)) {
      fail(`${sourceName}: duplicate action id ${action.id}`);
    }
    actionIDs.add(action.id);
    if (typeof action.label !== "string" || action.label.trim() === "") {
      fail(`${sourceName}: action ${action.id} needs label`);
    }
    if (typeof action.request !== "string" || action.request.trim() === "") {
      fail(`${sourceName}: action ${action.id} needs request`);
    }
    if (requestIDs.has(action.request) === false) {
      fail(`${sourceName}: action ${action.id} references missing request ${action.request}`);
    }
    if (action.requiresWritePermission === true && manifest.permissions.includes("write-actions") === false) {
      fail(`${sourceName}: action ${action.id} requires write-actions permission`);
    }
  }
}

export async function validatePluginPackage(pluginDirectory, manifest, sourceName) {
  const requestsFile = await readOptionalJSON(path.join(pluginDirectory, "requests.json"));
  const triggersFile = await readOptionalJSON(path.join(pluginDirectory, "triggers.json"));
  const eventsFile = await readOptionalJSON(path.join(pluginDirectory, "events.json"));
  const mappingsFile = await readOptionalJSON(path.join(pluginDirectory, "mappings.json"));
  const presetsFile = await readOptionalJSON(path.join(pluginDirectory, "rules.presets.json"));
  const viewsFile = await readOptionalJSON(path.join(pluginDirectory, "views.json"));
  const actionsFile = await readOptionalJSON(path.join(pluginDirectory, "actions.json"));

  const requestIDs = validateRequestDefinitions(manifest, requestsFile, sourceName);
  const eventTypes = validateEvents(eventsFile, sourceName);
  validateTriggers(triggersFile, requestIDs, sourceName);
  const resourceTypes = validateMappings(mappingsFile, requestIDs, eventTypes, sourceName);
  validateViews(viewsFile, resourceTypes, sourceName);
  validateActions(actionsFile, requestIDs, manifest, sourceName);
  validateRulePresets(presetsFile, eventTypes, sourceName);
}

export async function pluginFiles(pluginDirectory) {
  const names = (await readdir(pluginDirectory)).filter((name) => name.endsWith(".json")).sort();
  return Promise.all(names.map(async (name) => ({
    name,
    data: await readFile(path.join(pluginDirectory, name))
  })));
}

export async function validateLocalPluginDirectory(pluginDirectory, options = {}) {
  const sourceName = typeof options === "string" ? options : (options.sourceName ?? path.basename(pluginDirectory));
  const manifest = await readJSON(path.join(pluginDirectory, "manifest.json"));
  validateManifest(manifest, sourceName);
  await validatePluginPackage(pluginDirectory, manifest, sourceName);
  const files = await pluginFiles(pluginDirectory);
  const packageData = deterministicZip(files);
  const sha256 = createHash("sha256").update(packageData).digest("hex");
  return { manifest, sha256, checksum: sha256, packageData };
}
