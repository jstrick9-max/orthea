// Renders the LSO letterhead header and footer to PNG for the downloadable letters.
// Uses the same markup and print CSS as letterhead/letterhead.html, at the 6.8in
// content width of a US Letter page with 0.85in side margins.
//
//   NODE_PATH=$(npm root -g) node consult/downloads/tools/render-letterhead.mjs
//
// Writes consult/downloads/assets/header.png and footer.png.

import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const { chromium } = createRequire(import.meta.url)('playwright');
const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(here, '..', 'assets');

const LOGO = 'https://orthea-assets.s3.us-east-2.amazonaws.com/LSO-Letterhead-Logo.jpg';
const SCALE = 3; // 288 dpi — sharp in print, small enough to embed

const html = `<!doctype html>
<html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Jost:wght@400;500&display=block" rel="stylesheet">
<style>
  :root { --ink: #3d3836; --muted: #8b8481; --rule: #d9d4d1; }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { background: #fff; }
  body { font-family: "Jost", sans-serif; color: var(--ink); width: 6.8in; }
  #head, #foot { width: 6.8in; background: #fff; }
  #head { padding-bottom: 1px; }
  header { display: flex; justify-content: space-between; align-items: flex-end; }
  .doctors { text-align: right; font-size: 7pt; line-height: 1.6; letter-spacing: 0.06em; }
  .doctors .dr { font-weight: 500; text-transform: uppercase; letter-spacing: 0.14em; font-size: 6.6pt; }
  .doctors .cred { color: var(--muted); font-weight: 400; }
  .doctors .note { color: var(--muted); font-size: 6.4pt; letter-spacing: 0.12em; text-transform: uppercase; margin-top: 3pt; }
  .doctors .group + .group { margin-top: 7pt; }
  .rule { height: 0; border-top: 0.6pt solid var(--rule); margin-top: 20pt; }
  .logo { width: 1.75in; height: auto; display: block; }
  #foot { margin-top: 40px; }
  footer {
    border-top: 0.6pt solid var(--rule); padding-top: 12pt;
    display: flex; justify-content: center; align-items: center; gap: 12pt;
    font-size: 6.8pt; letter-spacing: 0.24em; text-transform: uppercase; color: var(--muted);
  }
  footer .dot { width: 2.5pt; height: 2.5pt; border-radius: 50%; background: var(--rule); }
  footer b { font-weight: 500; color: var(--ink); letter-spacing: 0.24em; }
</style></head>
<body>
<div id="head">
  <header>
    <img class="logo" src="${LOGO}" alt="Lemchen Salzer Orthodontics">
    <div class="doctors">
      <div class="group">
        <div><span class="dr">Marc S. Lemchen</span> <span class="cred">DMD</span></div>
        <div><span class="dr">Jennifer Salzer</span> <span class="cred">DDS</span></div>
        <div><span class="dr">Andrew T. Lemchen</span> <span class="cred">DMD</span></div>
        <div class="note">Diplomates, American Board of Orthodontics</div>
      </div>
      <div class="group">
        <div><span class="dr">Bina Park</span> <span class="cred">DDS</span></div>
      </div>
    </div>
  </header>
  <div class="rule"></div>
</div>
<div id="foot">
  <footer>
    <span>553 Park Avenue</span><span class="dot"></span>
    <span>New York, NY 10065</span><span class="dot"></span>
    <span>Tel <b>212.755.2333</b></span>
  </footer>
</div>
</body></html>`;

const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: SCALE, viewport: { width: 700, height: 600 } });
await page.setContent(html, { waitUntil: 'networkidle' });
await page.evaluate(() => document.fonts.ready);
const jost = await page.evaluate(() => document.fonts.check('500 10px Jost'));
if (!jost) throw new Error('Jost did not load — check network access to fonts.googleapis.com');

await page.locator('#head').screenshot({ path: path.join(out, 'header.png') });
await page.locator('footer').screenshot({ path: path.join(out, 'footer.png') });
await browser.close();
console.log('wrote header.png and footer.png to', out);
