// Renders every <section class="shot"> in page.html to ../images/<id>.png.
//
//   cd workshop/art && npm install && node render.mjs
//
// Needs Playwright; set PLAYWRIGHT_MODULE if it isn't resolvable from here.
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");

const out = path.join(here, "..", "images");
fs.mkdirSync(out, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1340, height: 900 } });
await page.goto("file://" + path.join(here, "page.html"));
await page.evaluate(() => document.fonts.ready);
// Transparent page so rounded corners blend into Steam's own background.
await page.addStyleTag({ content: "body { background: transparent !important }" });

const ids = await page.$$eval("section.shot", (els) => els.map((e) => e.id));
for (const id of ids) {
  await page.locator("#" + id).screenshot({ path: path.join(out, id + ".png"), omitBackground: true });
  console.log("wrote images/" + id + ".png");
}
await browser.close();
