// E02 · Read answer — check Claude's reply is the JSON we asked for.
const prev = $('Sign Claude').first().json;
const r = $input.first().json;
if (r.stop_reason === 'refusal') throw new Error('Claude declined this message');
const text = ((r.content || []).find(b => b.type === 'text') || {}).text || '';
const m = text.replace(/```(?:json)?/gi, '').match(/\{[\s\S]*\}/);
if (!m) throw new Error('Claude did not return JSON: ' + text.slice(0, 200));
let a;
try { a = JSON.parse(m[0]); } catch (e) { throw new Error('Claude returned invalid JSON: ' + e.message); }
const s = v => (v == null ? '' : String(v)).trim();
if (!s(a.chart_note)) throw new Error('Claude returned no chart note');
return [{ json: {
  itemId: String(prev.itemId),
  transcript: prev.transcript,
  summary: s(a.summary).slice(0, 500),
  chartNote: s(a.chart_note).slice(0, 5000),
  first: s(a.patient_first_name).slice(0, 80),
  last: s(a.patient_last_name).slice(0, 80),
  dob: /^\d{4}-\d{2}-\d{2}$/.test(s(a.patient_dob)) ? s(a.patient_dob) : ''
} }];
