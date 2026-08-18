import { chmod, mkdir, readFile, realpath, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const runtimeRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const output = resolve(runtimeRoot, "dist/quickchat-broker.js");
const projectRoot = await realpath(resolve(runtimeRoot, ".."));

await mkdir(dirname(output), { recursive: true });
await build({
  entryPoints: ["runtime/src/index.ts"],
  outfile: output,
  bundle: true,
  platform: "node",
  target: "node22",
  format: "esm",
  sourcemap: true,
  banner: { js: "#!/usr/bin/env node\nimport { createRequire as __quickchatCreateRequire } from \"node:module\";\nvar require = __quickchatCreateRequire(import.meta.url);" },
  legalComments: "external",
  absWorkingDir: projectRoot
});
const generatedBroker = await readFile(output, "utf8");
const brokerSource = generatedBroker.replaceAll(/^\/\/ .*\/node_modules\//gm, "// node_modules/");
if (brokerSource !== generatedBroker) await writeFile(output, brokerSource);
const mapPath = `${output}.map`;
const sourceMap = JSON.parse(await readFile(mapPath, "utf8"));
if (!Array.isArray(sourceMap.sources)) throw new Error("broker source map must contain sources");
sourceMap.sources = sourceMap.sources.map((source) => {
  if (typeof source !== "string") throw new Error("broker source map source must be a string");
  const nodeModules = source.indexOf("node_modules/");
  return nodeModules < 0 ? source : `../../${source.slice(nodeModules)}`;
});
await writeFile(mapPath, `${JSON.stringify(sourceMap)}\n`);
await chmod(output, 0o755);

for (const adapter of [
  { name: "codex-acp", entry: "@agentclientprotocol/codex-acp/dist/index.js" },
  { name: "claude-agent-acp", entry: "@agentclientprotocol/claude-agent-acp/dist/index.js" }
]) {
  const adapterOutput = resolve(runtimeRoot, `dist/adapters/${adapter.name}.js`);
  await mkdir(dirname(adapterOutput), { recursive: true });
  await build({
    entryPoints: [`node_modules/${adapter.entry}`],
    outfile: adapterOutput,
    bundle: true,
    platform: "node",
    target: "node22",
    format: "esm",
    sourcemap: false,
    legalComments: "external",
    absWorkingDir: projectRoot
  });
  const generatedAdapter = await readFile(adapterOutput, "utf8");
  const adapterSource = generatedAdapter.replaceAll(/^\/\/ .*\/node_modules\//gm, "// node_modules/");
  if (adapterSource !== generatedAdapter) await writeFile(adapterOutput, adapterSource);
  if (!adapterSource.startsWith("#!/usr/bin/env node\n") || adapterSource.startsWith("#!/usr/bin/env node\n#!")) {
    throw new Error(`${adapter.name} must contain exactly one leading Node.js shebang`);
  }
  await chmod(adapterOutput, 0o755);
}
