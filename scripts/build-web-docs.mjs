import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const outputPath = path.join(root, "web", "src", "generated", "docs.json");
const checkOnly = process.argv.includes("--check");
const repositoryBaseURL = "https://github.com/statusfoundry/status/blob/main";

const documents = [
  {
    slug: "doctrine",
    sourcePath: "DOCTRINE.md",
    summary: "Non-negotiable product beliefs for the native app, plugin model, local-first posture, and automation boundaries."
  },
  {
    slug: "spec",
    sourcePath: "SPEC.md",
    summary: "The product and technical source of truth for the core event pipeline, object model, plugin scope, and MVP."
  },
  {
    slug: "architecture",
    sourcePath: "docs/03-architecture.md",
    summary: "System boundaries, shared core responsibilities, persistence, app shells, registry, and future cloud relay boundaries."
  },
  {
    slug: "plugin-system",
    sourcePath: "docs/04-plugin-system.md",
    summary: "Declarative plugin package shape, permissions, registry hosting, publishing, trust levels, and install flow."
  },
  {
    slug: "events-automation",
    sourcePath: "docs/05-events-automation.md",
    summary: "Explainable rules, controlled actions, notification decisions, action runs, and audit output."
  },
  {
    slug: "integrations",
    sourcePath: "docs/06-integrations.md",
    summary: "Planned providers, MVP auth paths, normalized resources, events, metrics, and action boundaries."
  },
  {
    slug: "security-privacy",
    sourcePath: "docs/07-security-privacy.md",
    summary: "Local-first data handling, credential storage, plugin trust, signing, OAuth posture, and action safety."
  },
  {
    slug: "testing",
    sourcePath: "docs/18-testing.md",
    summary: "Required checks for StatusCore, StatusUI, schemas, registry, website, package fixtures, and CI."
  },
  {
    slug: "cloudflare-platform",
    sourcePath: "docs/19-cloudflare-platform.md",
    summary: "Pages, Workers, R2, registry API, package hosting, revocations, and deployment responsibilities."
  },
  {
    slug: "handoff-checklist",
    sourcePath: "docs/20-handoff-checklist.md",
    summary: "Operational runbook for agents and maintainers continuing implementation without product questions."
  },
  {
    slug: "plugin-author-guide",
    sourcePath: "docs/21-plugin-author-guide.md",
    summary: "How to copy the example template, validate a plugin locally, test in Developer Mode, and submit for registry review."
  }
];

function titleFromMarkdown(markdown, fallback) {
  const heading = markdown.match(/^#\s+(.+)$/m)?.[1]?.trim();
  return heading || fallback;
}

function fallbackTitle(sourcePath) {
  return path.basename(sourcePath, ".md")
    .replace(/^\d+-/, "")
    .split("-")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

const generated = {
  generatedAt: "2026-07-09T00:00:00Z",
  documents: await Promise.all(documents.map(async (document) => {
    const content = await readFile(path.join(root, document.sourcePath), "utf8");
    return {
      slug: document.slug,
      title: titleFromMarkdown(content, fallbackTitle(document.sourcePath)),
      path: `/docs/${document.slug}/`,
      sourcePath: document.sourcePath,
      sourceUrl: `${repositoryBaseURL}/${document.sourcePath}`,
      summary: document.summary,
      content
    };
  }))
};

const output = `${JSON.stringify(generated, null, 2)}\n`;

if (checkOnly) {
  const current = await readFile(outputPath, "utf8");
  if (current !== output) {
    throw new Error("web/src/generated/docs.json is out of date. Run npm run docs:build.");
  }
} else {
  await writeFile(outputPath, output);
  console.log(`Wrote ${generated.documents.length} documentation page(s) to web/src/generated/docs.json.`);
}
