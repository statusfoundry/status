import { readFile, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDocPathMap } from './lib/doc-path-map.mjs';
import { loadPublishers, resolveAuthor } from './lib/publishers.mjs';
import { renderMarkdown } from './lib/render-markdown.mjs';

const docPathMap = buildDocPathMap();

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outputPath = path.join(root, 'web', 'src', 'generated', 'plugins.json');
const publishersOutputPath = path.join(root, 'web', 'src', 'generated', 'publishers.json');
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

async function loadPluginDoc(pluginDirectory, publishers, { requireReadme }) {
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
  const { html: readmeHtml, toc: readmeToc } = await renderMarkdown(readme, { stripTitle: true, docPathMap });

  let iconSvg = null;
  try {
    const iconPath = path.join(pluginDirectory, 'icon.svg');
    const iconData = await readFile(iconPath, 'utf8');
    const trimmed = iconData.trim();
    if (trimmed.startsWith('<svg') && !/<script[\s>]/i.test(iconData) && !/\son[a-z]+\s*=/i.test(iconData) && !/<foreignObject[\s>]/i.test(iconData)) {
      iconSvg = trimmed;
    }
  } catch (error) {
    if (error?.code !== 'ENOENT') {
      throw error;
    }
  }

  return {
    id: manifest.id,
    name: manifest.name,
    summary,
    description: manifest.description,
    category: manifest.category,
    icon: manifest.icon ?? null,
    accentColor: manifest.accentColor ?? null,
    iconSvg,
    author: resolveAuthor(manifest.author, publishers),
    version: manifest.version,
    trustLevel,
    permissions: manifest.permissions,
    domains: manifest.domains,
    platforms: manifest.platforms,
    sourcePath,
    sourceUrl: `${repositoryBaseURL}/${sourcePath}`,
    websitePath: `/plugins/${manifest.id}/`,
    readmeTitle: titleFromMarkdown(readme, manifest.name),
    readmeHtml,
    readmeToc: readmeToc.map(({ id, text, depth }) => ({ id, text, depth })),
  };
}

function buildPublisherPages(publishers, plugins) {
  return publishers.map((publisher) => ({
    id: publisher.id,
    name: publisher.name,
    summary: publisher.summary,
    description: publisher.description,
    websiteUrl: publisher.websiteUrl,
    repositoryUrl: publisher.repositoryUrl,
    websitePath: `/publishers/${publisher.id}/`,
    plugins: plugins
      .filter((plugin) => plugin.author.publisherId === publisher.id)
      .map((plugin) => ({
        id: plugin.id,
        name: plugin.name,
        summary: plugin.summary,
        websitePath: plugin.websitePath,
        published: plugin.published,
      })),
  }));
}

async function main() {
  const publishers = await loadPublishers(root);
  const bundledRoot = path.join(root, 'plugins', 'bundled');
  const examplesRoot = path.join(root, 'plugins', 'examples');

  const bundledPlugins = await Promise.all(
    (await directoryNames(bundledRoot)).map((name) =>
      loadPluginDoc(path.join(bundledRoot, name), publishers, { requireReadme: true }),
    ),
  );

  const examplePlugins = await Promise.all(
    (await directoryNames(examplesRoot)).map((name) =>
      loadPluginDoc(path.join(examplesRoot, name), publishers, { requireReadme: true }),
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

  const publisherPages = {
    generatedAt: '2026-07-09T00:00:00Z',
    publishers: buildPublisherPages(publishers, plugins),
  };

  const pluginsOutput = `${JSON.stringify(generated, null, 2)}\n`;
  const publishersOutput = `${JSON.stringify(publisherPages, null, 2)}\n`;

  if (checkOnly) {
    const [currentPlugins, currentPublishers] = await Promise.all([
      readFile(outputPath, 'utf8'),
      readFile(publishersOutputPath, 'utf8'),
    ]);
    if (currentPlugins !== pluginsOutput) {
      throw new Error('web/src/generated/plugins.json is out of date. Run npm run plugins:docs:build.');
    }
    if (currentPublishers !== publishersOutput) {
      throw new Error('web/src/generated/publishers.json is out of date. Run npm run plugins:docs:build.');
    }
  } else {
    await writeFile(outputPath, pluginsOutput);
    await writeFile(publishersOutputPath, publishersOutput);
    console.log(`Wrote ${plugins.length} plugin documentation page(s) to web/src/generated/plugins.json.`);
    console.log(`Wrote ${publisherPages.publishers.length} publisher page(s) to web/src/generated/publishers.json.`);
  }
}

main().catch((error) => {
  console.error(error.message ?? error);
  process.exit(1);
});