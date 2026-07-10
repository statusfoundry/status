export const PUBLISHED_DOC_SOURCES = [
  { slug: 'doctrine', sourcePath: 'DOCTRINE.md' },
  { slug: 'spec', sourcePath: 'SPEC.md' },
  { slug: 'architecture', sourcePath: 'docs/03-architecture.md' },
  { slug: 'plugin-system', sourcePath: 'docs/04-plugin-system.md' },
  { slug: 'events-automation', sourcePath: 'docs/05-events-automation.md' },
  { slug: 'integrations', sourcePath: 'docs/06-integrations.md' },
  { slug: 'security-privacy', sourcePath: 'docs/07-security-privacy.md' },
  { slug: 'testing', sourcePath: 'docs/18-testing.md' },
  { slug: 'cloudflare-platform', sourcePath: 'docs/19-cloudflare-platform.md' },
  { slug: 'handoff-checklist', sourcePath: 'docs/20-handoff-checklist.md' },
  { slug: 'plugin-author-guide', sourcePath: 'docs/21-plugin-author-guide.md' },
];

export function buildDocPathMap(sources = PUBLISHED_DOC_SOURCES) {
  return Object.fromEntries(
    sources.map(({ slug, sourcePath }) => [sourcePath, `/docs/${slug}/`]),
  );
}