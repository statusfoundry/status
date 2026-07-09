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

async function createRenderer() {
  const highlighter = await createJavaScriptShikiHighlighter({
    themes: ['github-light'],
    langs: DOC_LANGS,
    defaultTheme: 'github-light',
    defaultLang: 'text',
  });

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

export function stripLeadingTitle(markdown) {
  return markdown.replace(/^#\s+[^\n]+\n+/, '');
}

export async function renderMarkdown(markdown, { stripTitle = false } = {}) {
  const source = stripTitle ? stripLeadingTitle(markdown) : markdown;
  const nizel = await getMarkdownRenderer();
  const { html, toc, readingTime } = await nizel(source);
  return { html, toc, readingTime };
}