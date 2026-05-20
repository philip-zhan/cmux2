import * as esbuild from "esbuild";
import { mkdir, writeFile, readFile, copyFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "..", "..");
const outDir = resolve(repoRoot, "Resources", "code-viewer");

await mkdir(outDir, { recursive: true });

const watch = process.argv.includes("--watch");

/** @type {import("esbuild").BuildOptions} */
const baseOptions = {
  entryPoints: [resolve(here, "src", "index.ts")],
  outfile: resolve(outDir, "code-viewer.js"),
  bundle: true,
  format: "esm",
  target: ["es2020"],
  platform: "browser",
  sourcemap: false,
  minify: true,
  legalComments: "none",
  logLevel: "info",
};

if (watch) {
  const ctx = await esbuild.context(baseOptions);
  await ctx.watch();
  console.log("code-viewer: watching for changes");
} else {
  const result = await esbuild.build(baseOptions);
  if (result.errors.length > 0) {
    process.exit(1);
  }
}

// Copy the HTML shell unchanged. Swift will inline the JS at runtime via a
// {{codeViewerJS}} placeholder substitution (same pattern as the markdown
// viewer shell). Doing the substitution in Swift keeps the build artifact
// shape stable and avoids re-running esbuild whenever the HTML changes.
await copyFile(resolve(here, "src", "shell.html"), resolve(outDir, "shell.html"));

const bytes = (await readFile(resolve(outDir, "code-viewer.js"))).byteLength;
console.log(`code-viewer.js: ${(bytes / 1024).toFixed(1)} KiB (uncompressed)`);

// Write a small manifest for build-time inspection / CI size gates.
await writeFile(
  resolve(outDir, "build-manifest.json"),
  JSON.stringify({ bytes, generatedAt: new Date().toISOString() }, null, 2)
);
