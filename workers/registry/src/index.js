import { registry, revocations } from "./registry-data.js";
import { pluginArtifacts } from "./plugin-artifacts.js";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, HEAD, OPTIONS",
  "access-control-allow-headers": "content-type"
};

function json(body, init = {}) {
  return new Response(JSON.stringify(body, null, 2), {
    ...init,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "public, max-age=60",
      ...corsHeaders,
      ...init.headers
    }
  });
}

function notFound(pathname) {
  return json(
    {
      error: "not_found",
      message: `No registry route exists for ${pathname}`
    },
    { status: 404, headers: { "cache-control": "no-store" } }
  );
}

function methodNotAllowed() {
  return json(
    {
      error: "method_not_allowed",
      message: "The registry API only supports GET, HEAD, and OPTIONS."
    },
    { status: 405, headers: { "cache-control": "no-store" } }
  );
}

async function artifact(pathname, method, env = {}) {
  if (pathname.startsWith("/plugins/") && env.PLUGIN_BUCKET) {
    const key = pathname.slice(1);
    const object = await env.PLUGIN_BUCKET.get(key);
    if (object) {
      return new Response(method === "HEAD" ? null : object.body, {
        headers: {
          "content-type": object.httpMetadata?.contentType ?? contentTypeForPath(pathname),
          "cache-control": "public, max-age=31536000, immutable",
          ...corsHeaders
        }
      });
    }
  }

  const item = pluginArtifacts[pathname];
  if (!item) {
    return undefined;
  }

  const bytes = Uint8Array.from(atob(item.bodyBase64), (character) => character.charCodeAt(0));
  return new Response(method === "HEAD" ? null : bytes, {
    headers: {
      "content-type": item.contentType,
      "cache-control": "public, max-age=31536000, immutable",
      ...corsHeaders
    }
  });
}

function contentTypeForPath(pathname) {
  if (pathname.endsWith(".zip")) {
    return "application/zip";
  }
  if (pathname.endsWith(".json")) {
    return "application/json; charset=utf-8";
  }
  return "application/octet-stream";
}

function pluginByID(pluginID) {
  return registry.plugins.find((plugin) => plugin.id === pluginID);
}

function versionByID(plugin, version) {
  return plugin.versions.find((candidate) => candidate.version === version);
}

function pluginSummary(plugin) {
  const latestVersion = plugin.versions[0];
  return {
    id: plugin.id,
    name: plugin.name,
    summary: plugin.summary,
    description: plugin.description,
    category: plugin.category,
    icon: plugin.icon,
    iconSvg: plugin.iconSvg,
    accentColor: plugin.accentColor,
    author: plugin.author,
    trustLevel: plugin.trustLevel,
    latestVersion: latestVersion?.version,
    platforms: latestVersion?.platforms ?? [],
    permissions: plugin.permissions,
    domains: plugin.domains
  };
}

function compatibleVersions(plugin, searchParams) {
  const platform = searchParams.get("platform");
  const coreVersion = searchParams.get("coreVersion");

  return plugin.versions.filter((version) => {
    if (platform && version.platforms.includes(platform) === false) {
      return false;
    }
    if (coreVersion && compareVersions(coreVersion, version.minCoreVersion) < 0) {
      return false;
    }
    return isVersionRevoked(plugin.id, version) === false;
  });
}

function isVersionRevoked(pluginID, version) {
  return revocations.revokedPlugins.includes(pluginID)
    || revocations.revokedVersions.some((item) => item.pluginId === pluginID && item.version === version.version)
    || revocations.revokedHashes.includes(version.sha256);
}

function compareVersions(lhs, rhs) {
  const left = lhs.split(".").map((part) => Number.parseInt(part, 10) || 0);
  const right = rhs.split(".").map((part) => Number.parseInt(part, 10) || 0);
  const count = Math.max(left.length, right.length);
  for (let index = 0; index < count; index += 1) {
    const delta = (left[index] ?? 0) - (right[index] ?? 0);
    if (delta !== 0) {
      return delta;
    }
  }
  return 0;
}

export async function route(request, env = {}) {
  const url = new URL(request.url);

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "GET" && request.method !== "HEAD") {
    return methodNotAllowed();
  }

  const artifactResponse = await artifact(url.pathname, request.method, env);
  if (artifactResponse) {
    return artifactResponse;
  }

  if (url.pathname === "/" || url.pathname === "/health") {
    return json({
      service: "status-registry",
      ok: true,
      generatedAt: new Date().toISOString()
    });
  }

  if (url.pathname === "/v1/registry") {
    return json({
      ...registry,
      generatedAt: new Date().toISOString()
    });
  }

  if (url.pathname === "/v1/revocations") {
    return json({
      ...revocations,
      generatedAt: new Date().toISOString()
    });
  }

  if (url.pathname === "/v1/plugins") {
    const plugins = registry.plugins
      .filter((plugin) => compatibleVersions(plugin, url.searchParams).length > 0)
      .map(pluginSummary);
    return json({
      schemaVersion: registry.schemaVersion,
      generatedAt: new Date().toISOString(),
      plugins
    });
  }

  const versionsMatch = url.pathname.match(/^\/v1\/plugins\/([^/]+)\/versions$/);
  if (versionsMatch) {
    const plugin = pluginByID(versionsMatch[1]);
    if (!plugin) {
      return notFound(url.pathname);
    }
    return json({
      pluginId: plugin.id,
      versions: compatibleVersions(plugin, url.searchParams)
    });
  }

  const versionMatch = url.pathname.match(/^\/v1\/plugins\/([^/]+)\/versions\/([^/]+)$/);
  if (versionMatch) {
    const plugin = pluginByID(versionMatch[1]);
    const version = plugin ? versionByID(plugin, versionMatch[2]) : undefined;
    if (!plugin || !version || isVersionRevoked(plugin.id, version)) {
      return notFound(url.pathname);
    }
    return json({
      pluginId: plugin.id,
      ...version
    });
  }

  const pluginMatch = url.pathname.match(/^\/v1\/plugins\/([^/]+)$/);
  if (pluginMatch) {
    const plugin = pluginByID(pluginMatch[1]);
    if (!plugin) {
      return notFound(url.pathname);
    }
    return json({
      ...plugin,
      versions: compatibleVersions(plugin, url.searchParams)
    });
  }

  return notFound(url.pathname);
}

export default {
  async fetch(request, env) {
    return route(request, env);
  }
};
