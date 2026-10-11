// E02 · Transcript text — pull the plain text out of Amazon Transcribe's result.
let r = $input.first().json;
if (typeof r === 'string') r = JSON.parse(r);
if (r && typeof r.data === 'string') r = JSON.parse(r.data);
const t = (((r || {}).results || {}).transcripts || []).map(x => x.transcript).join(' ').trim();
return [{ json: { transcript: t } }];
