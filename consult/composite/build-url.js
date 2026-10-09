// C03 · Build URL — turn the stored Budibase attachment URL into a full https URL,
// and refuse anything that isn't the practice's Budibase (no fetching arbitrary hosts).
const BUDIBASE = 'https://orthea-budibase.eqawdd.easypanel.host';
const ALLOWED = [new URL(BUDIBASE).host];

const row = $input.first().json;
let raw = String(row.composite_url || '').trim();
if (raw.startsWith('/')) raw = BUDIBASE + raw;
const url = new URL(raw);
if (url.protocol !== 'https:' || !ALLOWED.includes(url.host)) {
  throw new Error(`Composite URL host not allowed: ${url.host}`);
}
return [{ json: { id: row.id, source: row.composite_url, url: url.toString() } }];
