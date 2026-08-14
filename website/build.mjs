import { execFileSync } from "node:child_process";
import { cp, mkdir, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const source = fileURLToPath(new URL("./", import.meta.url));
const output = fileURLToPath(new URL("../dist/", import.meta.url));
const target = process.argv.includes("--target=rental") ? "rental" : "cloud";

await rm(output, { recursive: true, force: true });
await mkdir(join(output, "assets"), { recursive: true });

for (const file of await readdir(source)) {
  if (["build.mjs", "serve.mjs", "package-rental.mjs"].includes(file)) continue;
  if (target === "rental" && file === "server") continue;
  if (target === "cloud" && ["api", ".htaccess"].includes(file)) continue;
  await cp(join(source, file), join(output, file), {
    recursive: true
  });
}

await writeSitemapDates();

await cp(join(root, "docs", "support-manual.md"), join(output, "support-manual.md"));
if (target === "cloud") {
  await mkdir(join(output, ".openai"), { recursive: true });
  await cp(join(root, ".openai", "hosting.json"), join(output, ".openai", "hosting.json"));
}

console.log(`Built Stellise ${target} website in dist/`);

function day(date) {
  const pad = (value) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function git(args) {
  try {
    return execFileSync("git", args, { cwd: root, encoding: "utf8" }).trim();
  } catch {
    return "";
  }
}

async function lastChanged(file) {
  const path = join(source, file);
  if (git(["status", "--porcelain", "--", path])) return day(new Date());
  const committed = git(["log", "-1", "--format=%cs", "--", path]);
  if (committed) return committed;
  return day((await stat(path)).mtime);
}

async function pageDate(loc) {
  const path = new URL(loc).pathname;
  const page = path === "/" ? "index.html" : path.replace(/^\//, "");
  const html = await readFile(join(source, page), "utf8");
  const shared = ["styles.css", "script.js"].filter((asset) => html.includes(asset));
  const dates = await Promise.all([page, ...shared].map(lastChanged));
  return dates.sort().at(-1);
}

async function writeSitemapDates() {
  const sitemap = join(output, "sitemap.xml");
  const xml = await readFile(sitemap, "utf8");
  const entries = xml.match(/<url>[\s\S]*?<\/url>/g) ?? [];
  let updated = xml;
  for (const entry of entries) {
    const loc = entry.match(/<loc>(.*?)<\/loc>/)?.[1];
    if (!loc) continue;
    const rewritten = entry.replace(/<lastmod>.*?<\/lastmod>/, `<lastmod>${await pageDate(loc)}</lastmod>`);
    updated = updated.replace(entry, rewritten);
  }
  await writeFile(sitemap, updated);
}
