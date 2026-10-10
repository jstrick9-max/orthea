// Renders each SVG in brand/logos to PNG with transparent background (Chromium).
// Usage: node brand/render.cjs <logos dir>
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
(async () => {
  const dir = process.argv[2];
  const b = await chromium.launch();
  const jobs = [];
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.svg'))) {
    const stem = f.replace('.svg', '');
    if (stem.includes('favicon')) jobs.push([f, stem + '-32', 32], [f, stem + '-16', 16]);
    else if (stem.includes('icon')) jobs.push([f, stem + '-512', 512], [f, stem + '-180', 180]);
    else jobs.push([f, stem + '-160h', 160], [f, stem + '-80h', 80]);   // logo heights (2x and 1x)
  }
  for (const [f, out, h] of jobs) {
    const svg = fs.readFileSync(path.join(dir, f), 'utf8');
    const [, , vw, vh] = svg.match(/viewBox="([^"]+)"/)[1].split(' ').map(Number);
    const w = Math.round(h * vw / vh);
    const p = await b.newPage({ viewport: { width: w, height: h } });
    const html = `<html><body style="margin:0;background:transparent">${svg.replace(/width="[^"]+" height="[^"]+"/, `width="${w}" height="${h}"`)}</body></html>`;
    await p.setContent(html);
    await p.screenshot({ path: path.join(dir, out + '.png'), omitBackground: true, clip: { x: 0, y: 0, width: w, height: h } });
    await p.close();
  }
  await b.close();
})();
