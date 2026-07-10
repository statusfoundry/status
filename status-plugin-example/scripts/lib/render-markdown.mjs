import { useNizel } from 'nizel';
import { shikiPlugin } from 'nizel-plugin-shiki';
import { createJavaScriptShikiHighlighter } from 'nizel-plugin-shiki/javascript';

const DOC_LANGS = [
  'bash',
  'css',
  'html',
  'javascript',
  'json',
  'markdown',
  'scss',
  'sh',
  'shell',
  'sql',
  'swift',
  'text',
  'txt',
  'typescript',
  'yaml',
];

let rendererPromise;

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export function stripLeadingTitle(markdown) {
  return markdown.replace(/^#\s+[^\n]+\n+/, '');
}

export function linkifyPublishedDocReferences(markdown, docPathMap = {}) {
  let linked = markdown;
  const sourcePaths = Object.keys(docPathMap).sort((left, right) => right.length - left.length);

  for (const sourcePath of sourcePaths) {
    const href = docPathMap[sourcePath];
    linked = linked.replace(
      new RegExp(`\`${escapeRegExp(sourcePath)}\``, 'g'),
      `[${sourcePath}](${href})`,
    );
  }

  return linked;
}

function stripShikiInlineStyles(html) {
  return html
    .replace(/\sstyle="[^"]*"/g, '')
    .replace(/\bgithub-light\b/g, '')
    .replace(/\bgithub-dark\b/g, '')
    .replace(/class="shiki\s+"/g, 'class="shiki"')
    .replace(/class="shiki\s+"/g, 'class="shiki"');
}

async function createRenderer() {
  const baseHighlighter = await createJavaScriptShikiHighlighter({
    themes: ['github-light', 'github-dark'],
    langs: DOC_LANGS,
    defaultTheme: 'github-light',
    defaultLang: 'text',
  });

  const highlighter = (code, input) => {
    const highlighted = baseHighlighter(code, input);
    return typeof highlighted === 'string' ? stripShikiInlineStyles(highlighted) : highlighted;
  };

  return useNizel({
    preset: 'docs',
    plugins: [
      shikiPlugin({
        theme: 'github-light',
        highlighter,
      }),
    ],
  });
}

export async function getMarkdownRenderer() {
  if (!rendererPromise) {
    rendererPromise = createRenderer();
  }
  return rendererPromise;
}

export async function renderMarkdown(markdown, { stripTitle = false, docPathMap = {} } = {}) {
  const withLinks = linkifyPublishedDocReferences(markdown, docPathMap);
  const source = stripTitle ? stripLeadingTitle(withLinks) : withLinks;
  const nizel = await getMarkdownRenderer();
  const { html, toc, readingTime } = await nizel(source);
  return { html, toc, readingTime };
}