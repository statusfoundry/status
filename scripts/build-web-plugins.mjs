import { readFile, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outputPath = path.join(root, 'web', 'src', 'generated', 'plugins.json');
const registryPath = path.join(root, 'web', 'src', 'generated', 'registry.json');
const checkOnly = process.argv.includes('--check');
const repositoryBaseURL = 'https://github.com/statusfoundry/status/blob/main';

function titleFromMarkdown(markdown, fallback) {
  const heading = markdown.match(/^#\s+(.+)$/m)?.[1]?.trim();
  return heading || fallback;
}

async function directoryNames(directoryPath) {
  return (await readdir(directoryPath, { withFileTypes: true }))
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();
}

async function loadPluginDoc(pluginDirectory, { requireReadme }) {
  const readmePath = path.join(pluginDirectory, 'README.md');
  const manifestPath = path.join(pluginDirectory, 'manifest.json');
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));

  let readme;
  try {
    readme = await readFile(readmePath, 'utf8');
  } catch (error) {
    if (requireReadme && error?.code === 'ENOENT') {
      throw new Error(`${path.relative(root, pluginDirectory)} is missing README.md.`);
    }
    throw error;
  }

  let summary = manifest.description;
  let trustLevel = path.basename(path.dirname(pluginDirectory)) === 'bundled' ? 'official' : 'local-dev';

  try {
    const registry = JSON.parse(await readFile(path.join(pluginDirectory, 'registry.json'), 'utf8'));
    summary = registry.summary ?? summary;
    trustLevel = registry.trustLevel ?? trustLevel;
  } catch (error) {
    if (error?.code !== 'ENOENT') {
      throw error;
    }
  }

  const sourcePath = path.relative(root, readmePath).split(path.sep).join('/');

  return {
    id: manifest.id,
    name: manifest.name,
    summary,
    description: manifest.description,
    category: manifest.category,
    author: manifest.author,
    version: manifest.version,
    trustLevel,
    permissions: manifest.permissions,
    domains: manifest.domains,
    platforms: manifest.platforms,
    sourcePath,
    sourceUrl: `${repositoryBaseURL}/${sourcePath}`,
    websitePath: `/plugins/${manifest.id}/`,
    readmeTitle: titleFromMarkdown(readme, manifest.name),
    readme,
  };
}

async function main() {
  const bundledRoot = path.join(root, 'plugins', 'bundled');
  const examplesRoot = path.join(root, 'plugins', 'examples');

  const bundledPlugins = await Promise.all(
    (await directoryNames(bundledRoot)).map((name) =>
      loadPluginDoc(path.join(bundledRoot, name), { requireReadme: true }),
    ),
  );

  const examplePlugins = await Promise.all(
    (await directoryNames(examplesRoot)).map((name) =>
      loadPluginDoc(path.join(examplesRoot, name), { requireReadme: true }),
    ),
  );

  let registryPluginIDs = new Set();
  try {
    const registry = JSON.parse(await readFile(registryPath, 'utf8'));
    registryPluginIDs = new Set(registry.plugins.map((plugin) => plugin.id));
  } catch (error) {
    if (error?.code !== 'ENOENT') {
      throw error;
    }
  }

  const plugins = [...bundledPlugins, ...examplePlugins]
    .sort((left, right) => left.name.localeCompare(right.name))
    .map((plugin) => ({
      ...plugin,
      published: registryPluginIDs.has(plugin.id),
    }));

  const generated = {
    generatedAt: '2026-07-09T00:00:00Z',
    plugins,
  };

  const output = `${JSON.stringify(generated, null, 2)}\n`;

  if (checkOnly) {
    const current = await readFile(outputPath, 'utf8');
    if (current !== output) {
      throw new Error('web/src/generated/plugins.json is out of date. Run npm run plugins:docs:build.');
    }
  } else {
    await writeFile(outputPath, output);
    console.log(`Wrote ${plugins.length} plugin documentation page(s) to web/src/generated/plugins.json.`);
  }
}

main().catch((error) => {
  console.error(error.message ?? error);
  process.exit(1);
});