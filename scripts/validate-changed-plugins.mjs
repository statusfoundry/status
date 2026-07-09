import { execSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateLocalPluginDirectory } from './lib/plugin-package-validator.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');

const PLUGIN_PATH_PATTERN = /^(plugins\/(?:bundled|examples)\/[^/]+|status-plugin-example\/plugin)\//;

function gitDiffNames(base, head) {
  const output = execSync(`git diff --name-only ${base} ${head}`, {
    cwd: repoRoot,
    encoding: 'utf8',
  });
  return output.trim().split('\n').filter(Boolean);
}

function resolveGitRange() {
  const base = process.env.GITHUB_BASE_SHA;
  const head = process.env.GITHUB_SHA;
  if (base && head) {
    return { base, head };
  }

  try {
    execSync('git rev-parse --verify main', { cwd: repoRoot, stdio: 'ignore' });
    const mergeBase = execSync('git merge-base main HEAD', {
      cwd: repoRoot,
      encoding: 'utf8',
    }).trim();
    return { base: mergeBase, head: 'HEAD' };
  } catch {
    return { base: 'HEAD~1', head: 'HEAD' };
  }
}

function pluginDirectories(changedFiles) {
  const directories = new Set();

  for (const file of changedFiles) {
    if (PLUGIN_PATH_PATTERN.test(file) === false) {
      continue;
    }

    if (file.startsWith('status-plugin-example/plugin/')) {
      directories.add(path.join(repoRoot, 'status-plugin-example/plugin'));
      continue;
    }

    const parts = file.split('/');
    directories.add(path.join(repoRoot, parts[0], parts[1], parts[2]));
  }

  return [...directories].sort();
}

async function main() {
  const { base, head } = resolveGitRange();
  const changedFiles = gitDiffNames(base, head);
  const directories = pluginDirectories(changedFiles);

  if (directories.length === 0) {
    console.log('No plugin directories changed in this revision range.');
    return;
  }

  console.log(`Validating ${directories.length} changed plugin director${directories.length === 1 ? 'y' : 'ies'}:`);

  for (const directory of directories) {
    const sourceName = path.relative(repoRoot, directory);
    const result = await validateLocalPluginDirectory(directory, sourceName);
    console.log(`Validated ${result.manifest.id}@${result.manifest.version} (${sourceName})`);
    console.log(`SHA-256: ${result.sha256}`);
  }
}

main().catch((error) => {
  console.error(error.message ?? error);
  process.exit(1);
});