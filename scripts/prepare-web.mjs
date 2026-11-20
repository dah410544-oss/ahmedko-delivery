import { mkdir, copyFile } from "node:fs/promises";

const files = [
  "index.html",
  "admin.html",
  "driver.html",
  "restaurant.html",
  "customer.html",
  "privacy.html",
  "taj-menu.html",
  "auto-o2-menu.js",
  "manifest.webmanifest",
  "service-worker.js",
  "icon.svg"
];

await mkdir("www", { recursive: true });
for (const file of files) {
  await copyFile(file, `www/${file}`);
}
console.log("Prepared AHMEDKO web app bundle:", files.join(", "));
