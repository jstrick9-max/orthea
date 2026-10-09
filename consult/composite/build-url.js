// C03 · Build URL — turn the stored Budibase attachment URL into a full https URL
// on the practice's Budibase (no fetching arbitrary hosts).
// Budibase may store the link as "/files/signed/…", or as an absolute URL on an
// internal / http host; any Budibase file path is re-pointed at the public host.
const BUDIBASE = 'https://orthea-budibase.eqawdd.easypanel.host';
const ALLOWED = [new URL(BUDIBASE).host];

const row = $input.first().json;
const raw = String(row.composite_url || '').trim();
const url = new URL(raw, BUDIBASE);
if (/^\/(files|api\/assets|prod-budi-app-assets|app_)/.test(url.pathname)) {
  url.protocol = 'https:';
  url.hostname = new URL(BUDIBASE).hostname;
  url.port = '';
}
if (url.protocol !== 'https:' || !ALLOWED.includes(url.host)) {
  throw new Error(`Composite URL host not allowed: ${url.host}`);
}
return [{ json: { id: row.id, source: row.composite_url, url: url.toString() } }];
