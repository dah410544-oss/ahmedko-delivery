import { readFile } from "node:fs/promises";
import vm from "node:vm";

const htmlFiles = [
  "index.html",
  "admin.html",
  "driver.html",
  "customer.html",
  "privacy.html",
  "taj-menu.html"
];
const standaloneScripts = ["auto-o2-menu.js", "service-worker.js"];
let checked = 0;

for (const file of htmlFiles) {
  const source = await readFile(file, "utf8");
  const scripts = source.matchAll(/<script\\b([^>]*)>([\\s\\S]*?)<\\/script\\s*>/gi);
  let index = 0;
  for (const match of scripts) {
    if (/\\bsrc\\s*=/.test(match[1])) continue;
    const code = match[2].trim();
    if (!code) continue;
    new vm.Script(code, { filename: file + "#inline-script-" + (++index) });
    checked++;
  }
}
for (const file of standaloneScripts) {
  const source = await readFile(file, "utf8");
  new vm.Script(source, { filename: file });
  checked++;
}
console.log("JavaScript syntax check passed for " + checked + " inline/standalone scripts.");
