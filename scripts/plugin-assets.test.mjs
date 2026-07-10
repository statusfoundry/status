import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { pluginFiles } from "./lib/plugin-package-validator.mjs";
import { validatePluginSVG } from "./lib/plugin-svg-validator.mjs";

test("validatePluginSVG accepts internal gradients and use references", () => {
  const svg = `
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
      <defs>
        <linearGradient id="bg"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#fff"/></linearGradient>
        <symbol id="glyph"><path d="M4 4h24v24H4z"/></symbol>
      </defs>
      <rect width="32" height="32" fill="url(#bg)"/>
      <use href="#glyph"/>
    </svg>
  `;

  assert.equal(validatePluginSVG(svg, "valid.svg").startsWith("<svg"), true);
});

test("validatePluginSVG rejects executable or remote SVG content", () => {
  const cases = [
    `<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>`,
    `<svg xmlns="http://www.w3.org/2000/svg"><rect onload="alert(1)"/></svg>`,
    `<svg xmlns="http://www.w3.org/2000/svg"><image href="https://example.com/logo.png"/></svg>`,
    `<svg xmlns="http://www.w3.org/2000/svg"><style>svg{fill:red}</style></svg>`,
    `<svg xmlns="http://www.w3.org/2000/svg"><use href="https://example.com/icon.svg#glyph"/></svg>`
  ];

  for (const [index, svg] of cases.entries()) {
    assert.throws(() => validatePluginSVG(svg, `invalid-${index}.svg`));
  }
});

test("pluginFiles includes README.md and icon.svg deterministically", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "status-plugin-assets-"));
  await mkdir(directory, { recursive: true });
  await writeFile(path.join(directory, "manifest.json"), "{}\n");
  await writeFile(path.join(directory, "README.md"), "# Example\n");
  await writeFile(path.join(directory, "icon.svg"), `<svg xmlns="http://www.w3.org/2000/svg"></svg>`);

  const files = await pluginFiles(directory);

  assert.deepEqual(files.map((file) => file.name), ["README.md", "icon.svg", "manifest.json"]);
  assert.equal((await readFile(path.join(directory, "README.md"), "utf8")).startsWith("# Example"), true);
});
