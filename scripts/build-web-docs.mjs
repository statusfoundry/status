import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDocPathMap } from './lib/doc-path-map.mjs';
import { renderMarkdown } from './lib/render-markdown.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const indexOutputPath = path.join(root, 'web', 'src', 'generated', 'docs-index.json');
const contentOutputPath = path.join(root, 'web', 'src', 'generated', 'docs.json');
const checkOnly = process.argv.includes('--check');
const repositoryBaseURL = 'https://github.com/statusfoundry/status/blob/main';
const docPathMap = buildDocPathMap();

const documents = [
  {
    slug: 'doctrine',
    sourcePath: 'DOCTRINE.md',
    summary: 'Non-negotiable product beliefs for the native app, plugin model, local-first posture, and automation boundaries.',
  },
  {
    slug: 'spec',
    sourcePath: 'SPEC.md',
    summary: 'The product and technical source of truth for the core event pipeline, object model, plugin scope, and MVP.',
  },
  {
    slug: 'architecture',
    sourcePath: 'docs/03-architecture.md',
    summary: 'System boundaries, shared core responsibilities, persistence, app shells, registry, and future cloud relay boundaries.',
  },
  {
    slug: 'plugin-system',
    sourcePath: 'docs/04-plugin-system.md',
    summary: 'Declarative plugin package shape, permissions, registry hosting, publishing, trust levels, and install flow.',
  },
  {
    slug: 'events-automation',
    sourcePath: 'docs/05-events-automation.md',
    summary: 'Explainable rules, controlled actions, notification decisions, action runs, and audit output.',
  },
  {
    slug: 'integrations',
    sourcePath: 'docs/06-integrations.md',
    summary: 'Planned providers, MVP auth paths, normalized resources, events, metrics, and action boundaries.',
  },
  {
    slug: 'security-privacy',
    sourcePath: 'docs/07-security-privacy.md',
    summary: 'Local-first data handling, credential storage, plugin trust, signing, OAuth posture, and action safety.',
  },
  {
    slug: 'testing',
    sourcePath: 'docs/18-testing.md',
    summary: 'Required checks for StatusCore, StatusUI, schemas, registry, website, package fixtures, and CI.',
  },
  {
    slug: 'cloudflare-platform',
    sourcePath: 'docs/19-cloudflare-platform.md',
    summary: 'Pages, Workers, R2, registry API, package hosting, revocations, and deployment responsibilities.',
  },
  {
    slug: 'handoff-checklist',
    sourcePath: 'docs/20-handoff-checklist.md',
    summary: 'Operational runbook for agents and maintainers continuing implementation without product questions.',
  },
  {
    slug: 'plugin-author-guide',
    sourcePath: 'docs/21-plugin-author-guide.md',
    summary: 'How to copy the example template, validate a plugin locally, test in Developer Mode, and submit for registry review.',
  },
  {
    slug: 'plugin-governance',
    sourcePath: 'docs/22-plugin-governance.md',
    summary: 'Repository model, trust levels, third-party review path, signing, publication, and revocation rules for Status plugins.',
  },
];

function titleFromMarkdown(markdown, fallback) {
  const heading = markdown.match(/^#\s+(.+)$/m)?.[1]?.trim();
  return heading || fallback;
}

function fallbackTitle(sourcePath) {
  return path.basename(sourcePath, '.md')
    .replace(/^\d+-/, '')
    .split('-')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

async function main() {
  const renderedDocuments = await Promise.all(documents.map(async (document) => {
    const markdown = await readFile(path.join(root, document.sourcePath), 'utf8');
    const { html, toc } = await renderMarkdown(markdown, { stripTitle: true, docPathMap });
    const title = titleFromMarkdown(markdown, fallbackTitle(document.sourcePath));

    return {
      slug: document.slug,
      title,
      path: `/docs/${document.slug}/`,
      sourcePath: document.sourcePath,
      sourceUrl: `${repositoryBaseURL}/${document.sourcePath}`,
      summary: document.summary,
      html,
      toc: toc.map(({ id, text, depth }) => ({ id, text, depth })),
    };
  }));

  const generatedAt = '2026-07-09T00:00:00Z';
  const indexGenerated = {
    generatedAt,
    documents: renderedDocuments.map(({ slug, title, path, sourcePath, sourceUrl, summary }) => ({
      slug,
      title,
      path,
      sourcePath,
      sourceUrl,
      summary,
    })),
  };
  const contentGenerated = {
    generatedAt,
    documents: renderedDocuments.map(({ slug, title, sourcePath, sourceUrl, summary, html, toc }) => ({
      slug,
      title,
      sourcePath,
      sourceUrl,
      summary,
      html,
      toc,
    })),
  };

  const indexOutput = `${JSON.stringify(indexGenerated, null, 2)}\n`;
  const contentOutput = `${JSON.stringify(contentGenerated, null, 2)}\n`;

  if (checkOnly) {
    const [currentIndex, currentContent] = await Promise.all([
      readFile(indexOutputPath, 'utf8'),
      readFile(contentOutputPath, 'utf8'),
    ]);
    if (currentIndex !== indexOutput) {
      throw new Error('web/src/generated/docs-index.json is out of date. Run npm run docs:build.');
    }
    if (currentContent !== contentOutput) {
      throw new Error('web/src/generated/docs.json is out of date. Run npm run docs:build.');
    }
  } else {
    await Promise.all([
      writeFile(indexOutputPath, indexOutput),
      writeFile(contentOutputPath, contentOutput),
    ]);
    console.log(`Wrote ${indexGenerated.documents.length} documentation index entries to web/src/generated/docs-index.json.`);
    console.log(`Wrote ${contentGenerated.documents.length} documentation page(s) to web/src/generated/docs.json.`);
  }
}

main().catch((error) => {
  console.error(error.message ?? error);
  process.exit(1);
});
