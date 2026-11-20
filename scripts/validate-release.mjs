import { access, readFile } from "node:fs/promises";

const requiredFiles = [
  "www/index.html",
  "www/customer.html",
  "www/driver.html",
  "www/admin.html",
  "www/privacy.html",
  "www/manifest.webmanifest",
  "www/service-worker.js",
  "www/icon.svg"
];

for (const file of requiredFiles) {
  try {
    await access(file);
  } catch {
    throw new Error("Release bundle is missing required file: " + file);
  }
}

const manifest = JSON.parse(await readFile("www/manifest.webmanifest", "utf8"));
if (manifest.display !== "standalone" || !manifest.start_url || !manifest.scope) {
  throw new Error("PWA manifest is missing standalone install settings.");
}
if (!Array.isArray(manifest.icons) || manifest.icons.length === 0) {
  throw new Error("PWA manifest has no application icon.");
}
const config = JSON.parse(await readFile("capacitor.config.json", "utf8"));
if (config.appId !== "com.ahmedko.delivery" || config.webDir !== "www") {
  throw new Error("Unexpected Capacitor appId or webDir.");
}

for (const file of ["www/index.html", "www/customer.html", "www/driver.html", "www/admin.html"]) {
  const source = await readFile(file, "utf8");
  if (/service_role|SUPABASE_SERVICE_ROLE|-----BEGIN (RSA|EC|OPENSSH) PRIVATE KEY-----/i.test(source)) {
    throw new Error("Potential server secret or private key found in " + file);
  }
  if (!source.includes("https://")) {
    throw new Error("Expected secure HTTPS service endpoints in " + file);
  }
}

const customer = await readFile("www/customer.html", "utf8");
if (!customer.includes('rpc("create_customer_order"') ||
    !customer.includes("signInWithOtp") ||
    !customer.includes('rpc("get_my_customer_orders"')) {
  throw new Error("Customer order creation or verified-phone tracking flow is incomplete.");
}

const driver = await readFile("www/driver.html", "utf8");
if (!driver.includes('rpc("driver_update_order_status"')) {
  throw new Error("Driver status updates are not routed through the protected RPC.");
}

console.log("AHMEDKO release validation passed: web bundle, manifest, app identity, privacy page and protected flows.");
