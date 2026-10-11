// E02 · Error text — something failed: record a short reason on the message (no patient data).
const e = $input.first().json;
const msg = String((e.error && (e.error.message || e.error)) || e.message || 'Processing failed').slice(0, 500);
return [{ json: { itemId: String($('Load item').first().json.id), error: msg } }];
