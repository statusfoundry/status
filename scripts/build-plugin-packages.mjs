import { createHash, createPrivateKey, sign } from "node:crypto";
import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  deterministicZip,
  fail,
  pluginFiles,
  validateLocalPluginDirectory,
  validateManifest,
  validatePluginPackage,
} from "./lib/plugin-package-validator.mjs";
import { loadPublishers, resolveAuthor } from "./lib/publishers.mjs";
import { validatePluginSVG } from "./lib/plugin-svg-validator.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const pluginsRoot = path.join(root, "plugins", "bundled");
const examplePluginsRoot = path.join(root, "plugins", "examples");
const registryDataPath = path.join(root, "workers", "registry", "src", "registry-data.js");
const artifactsPath = path.join(root, "workers", "registry", "src", "plugin-artifacts.js");
const webRegistryPath = path.join(root, "web", "src", "generated", "registry.json");
const packageDistRoot = path.join(root, "workers", "registry", "dist", "plugins");
const swiftBundledPluginsRoot = path.join(root, "Sources", "StatusCore", "Resources", "BundledPlugins");
const registryBaseURL = "https://status-registry.hakobs.com";
const checkOnly = process.argv.includes("--check");
const localPluginFlagIndex = process.argv.indexOf("--local-plugin");
const localPluginPath = localPluginFlagIndex === -1 ? undefined : process.argv[localPluginFlagIndex + 1];
const devSigningPrivateKey = createPrivateKey(`-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIHMXJtFn66hGp93MMMQcTOgQqxOXHNsvw0iUwxMTdhaZ
-----END PRIVATE KEY-----`);

async function readJSON(filePath) {
  return JSON.parse(await readFile(filePath, "utf8"));
}

async function readOptionalText(filePath) {
  try {
    return await readFile(filePath, "utf8");
  } catch (error) {
    if (error?.code === "ENOENT") {
      return null;
    }
    throw error;
  }
}

async function directoryNames(directoryPath) {
  try {
    return (await readdir(directoryPath, { withFileTypes: true }))
      .filter((entry) => entry.isDirectory())
      .map((entry) => entry.name)
      .sort();
  } catch (error) {
    if (error?.code === "ENOENT") {
      return [];
    }
    throw error;
  }
}


function jsModule(name, value) {
  return `export const ${name} = ${JSON.stringify(value, null, 2)};\n`;
}

async function build() {
  if (localPluginFlagIndex !== -1) {
    if (!localPluginPath) {
      fail("--local-plugin requires a plugin directory path");
    }
    const pluginDirectory = path.resolve(process.cwd(), localPluginPath);
    const sourceName = `local/${path.basename(pluginDirectory)}`;
    const { manifest, sha256 } = await validateLocalPluginDirectory(pluginDirectory, sourceName);
    console.log(`Validated local plugin ${manifest.id}@${manifest.version}`);
    console.log(`Package: ${manifest.id}-${manifest.version}.statusplugin.zip`);
    console.log(`SHA-256: ${sha256}`);
    console.log("Trust: local-dev (unsigned; Developer Mode only)");
    return;
  }

  const publishers = await loadPublishers(root);
  const pluginDirectoryNames = await directoryNames(pluginsRoot);
  const exampleDirectoryNames = await directoryNames(examplePluginsRoot);

  const plugins = [];
  const bundledPlugins = [];
  const bundledResourceFiles = {};
  const artifacts = {};

  for (const directoryName of pluginDirectoryNames) {
    const pluginDirectory = path.join(pluginsRoot, directoryName);
    const manifest = await readJSON(path.join(pluginDirectory, "manifest.json"));
    const metadata = await readJSON(path.join(pluginDirectory, "registry.json"));
    const iconText = await readOptionalText(path.join(pluginDirectory, "icon.svg"));
    const iconSvg = iconText ? validatePluginSVG(iconText, `${directoryName}: icon.svg`) : null;
    validateManifest(manifest, directoryName, publishers);
    await validatePluginPackage(pluginDirectory, manifest, directoryName);
    const author = resolveAuthor(manifest.author, publishers);

    const files = await pluginFiles(pluginDirectory);
    const packageData = deterministicZip(files);
    const sha256 = createHash("sha256").update(packageData).digest("hex");
    const packagePath = `/plugins/${manifest.id}/${manifest.version}/${manifest.id}-${manifest.version}.statusplugin.zip`;
    const manifestPath = `/plugins/${manifest.id}/${manifest.version}/manifest.json`;
    const signature = sign(null, packageData, devSigningPrivateKey).toString("base64");

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
      icon: manifest.icon,
      iconSvg,
      accentColor: manifest.accentColor,
      author,
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
    bundledPlugins.push({
      id: manifest.id,
      version: manifest.version,
      trustLevel: metadata.trustLevel,
      minCoreVersion: manifest.minCoreVersion,
      platforms: manifest.platforms,
      domains: manifest.domains,
      sha256,
      signature,
      signedBy: metadata.signedBy,
      releasedAt: metadata.releasedAt,
      packageResourceName: `${manifest.id}-${manifest.version}.statusplugin.zip`,
      manifestResourceName: `${manifest.id}-${manifest.version}-manifest.json`
    });
    bundledResourceFiles[`${manifest.id}-${manifest.version}.statusplugin.zip`] = packageData;
    bundledResourceFiles[`${manifest.id}-${manifest.version}-manifest.json`] = Buffer.from(JSON.stringify(manifest, null, 2) + "\n");

    const distDirectory = path.join(packageDistRoot, manifest.id, manifest.version);
    if (!checkOnly) {
      await mkdir(distDirectory, { recursive: true });
      await writeFile(path.join(distDirectory, `${manifest.id}-${manifest.version}.statusplugin.zip`), packageData);
      await writeFile(path.join(distDirectory, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");

      await mkdir(swiftBundledPluginsRoot, { recursive: true });
      await writeFile(path.join(swiftBundledPluginsRoot, `${manifest.id}-${manifest.version}.statusplugin.zip`), packageData);
      await writeFile(
        path.join(swiftBundledPluginsRoot, `${manifest.id}-${manifest.version}-manifest.json`),
        JSON.stringify(manifest, null, 2) + "\n"
      );
    }
  }

  for (const directoryName of exampleDirectoryNames) {
    const pluginDirectory = path.join(examplePluginsRoot, directoryName);
    const manifest = await readJSON(path.join(pluginDirectory, "manifest.json"));
    validateManifest(manifest, `examples/${directoryName}`, publishers);
    await validatePluginPackage(pluginDirectory, manifest, `examples/${directoryName}`);
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
  const bundledPluginIndexJSON = JSON.stringify(
    {
      schemaVersion: "1.0.0",
      generatedAt: "2026-07-07T12:00:00Z",
      plugins: bundledPlugins
    },
    null,
    2
  ) + "\n";

  if (checkOnly) {
    const [currentRegistry, currentArtifacts, currentWebRegistry, currentBundledPluginIndex] = await Promise.all([
      readFile(registryDataPath, "utf8"),
      readFile(artifactsPath, "utf8"),
      readFile(webRegistryPath, "utf8"),
      readFile(path.join(swiftBundledPluginsRoot, "index.json"), "utf8")
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
    if (currentBundledPluginIndex !== bundledPluginIndexJSON) {
      fail("Sources/StatusCore/Resources/BundledPlugins/index.json is out of date. Run npm run plugins:build.");
    }
    for (const [resourceName, expectedData] of Object.entries(bundledResourceFiles)) {
      const currentData = await readFile(path.join(swiftBundledPluginsRoot, resourceName));
      if (Buffer.compare(currentData, expectedData) !== 0) {
        fail(`Sources/StatusCore/Resources/BundledPlugins/${resourceName} is out of date. Run npm run plugins:build.`);
      }
    }
  } else {
    await mkdir(path.dirname(webRegistryPath), { recursive: true });
    await mkdir(swiftBundledPluginsRoot, { recursive: true });
    await writeFile(registryDataPath, registryModule);
    await writeFile(artifactsPath, artifactModule);
    await writeFile(webRegistryPath, webRegistryJSON);
    await writeFile(path.join(swiftBundledPluginsRoot, "index.json"), bundledPluginIndexJSON);
  }

  const exampleSummary = exampleDirectoryNames.length === 0 ? "" : ` and validated ${exampleDirectoryNames.length} example plugin(s)`;
  console.log(`${checkOnly ? "Checked" : "Built"} ${plugins.length} plugin package(s)${exampleSummary}.`);
}

await build();
