// E02 · Pick voice note — the first audio attachment Amazon Transcribe can read.
const TRANSCRIBE_OK = { m4a: 'mp4', mp4: 'mp4', mp3: 'mp3', wav: 'wav', flac: 'flac', ogg: 'ogg', oga: 'ogg', opus: 'ogg', amr: 'amr', webm: 'webm' };
const item = $input.first().json;
let atts = item.attachments;
if (typeof atts === 'string') { try { atts = JSON.parse(atts); } catch (e) { atts = []; } }
atts = Array.isArray(atts) ? atts : [];
const audio = atts.filter(a => a.kind === 'audio');
const ext = a => (String(a.name || a.key || '').match(/\.([a-z0-9]+)$/i) || [, ''])[1].toLowerCase();
const usable = audio.find(a => TRANSCRIBE_OK[ext(a)]);
const notes = audio.filter(a => !TRANSCRIBE_OK[ext(a)]).map(a => `Voice note "${a.name}" is in a format Orthea can't transcribe yet (.${ext(a) || '?'}).`);
return [{ json: {
  itemId: String(item.id),
  hasAudio: !!usable,
  audioKey: usable ? usable.key : '',
  mediaFormat: usable ? TRANSCRIBE_OK[ext(usable)] : '',
  attachments: atts,
  notes
} }];
