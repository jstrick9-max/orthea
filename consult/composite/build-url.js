// C03 · Build URL — turn the stored Budibase attachment URL into a full https URL
// on the practice's Budibase (no fetching arbitrary hosts).
// Budibase may store the link as "/files/signed/…", or as an absolute URL on an
// internal / http host; any Budibase file path is re-pointed at the public host.
// (n8n's Code sandbox has no URL class, so this is plain string handling.)
const BUDIBASE = 'https://orthea-budibase.eqawdd.easypanel.host';

const row = $input.first().json;
const raw = String(row.composite_url || '').trim();
const m = raw.match(/^(?:([a-z][a-z0-9+.-]*):\/\/([^/?#]+))?(\/[^\s]*)$/i);
if (!m) throw new Error(`Composite URL not recognised: ${raw.slice(0, 60)}`);
const [, scheme, host, path] = m;
const budibaseFile = /^\/(files|api\/assets|prod-budi-app-assets|app_)/.test(path);
const sameHost = scheme && scheme.toLowerCase() === 'https'
  && host.toLowerCase() === BUDIBASE.slice('https://'.length);
if (scheme && !budibaseFile && !sameHost) {
  throw new Error(`Composite URL host not allowed: ${host}`);
}
return [{ json: { id: row.id, source: row.composite_url, url: BUDIBASE + path } }];
