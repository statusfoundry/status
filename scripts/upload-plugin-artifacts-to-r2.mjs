import { readdir, stat } from "node:fs/promises";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const distRoot = path.join(root, "workers", "registry", "dist", "plugins");
const bucket = process.env.STATUS_PLUGIN_BUCKET ?? "status-plugins";
const accountID = process.env.CLOUDFLARE_ACCOUNT_ID;

async function filesIn(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await filesIn(entryPath));
    } else if (entry.isFile()) {
      files.push(entryPath);
    }
  }
  return files.sort();
}

function contentType(filePath) {
  if (filePath.endsWith(".zip")) {
    return "application/zip";
  }
  if (filePath.endsWith(".json")) {
    return "application/json; charset=utf-8";
  }
  return "application/octet-stream";
}

try {
  const info = await stat(distRoot);
  if (info.isDirectory() === false) {
    throw new Error(`${distRoot} is not a directory`);
  }
} catch {
  throw new Error("Plugin artifact dist is missing. Run npm run plugins:build before uploading to R2.");
}

const files = await filesIn(distRoot);
for (const file of files) {
  const relativeKey = path.relative(path.join(root, "workers", "registry", "dist"), file).split(path.sep).join("/");
  const target = `${bucket}/${relativeKey}`;
  const args = ["wrangler", "r2", "object", "put", target, "--remote", "--file", file, "--content-type", contentType(file)];
  if (accountID) {
    args.push("--account-id", accountID);
  }
  const result = spawnSync(
    "npx",
    args,
    { stdio: "inherit", cwd: root }
  );
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

console.log(`Uploaded ${files.length} plugin artifact(s) to R2 bucket ${bucket}.`);
