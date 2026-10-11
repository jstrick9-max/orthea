// E01 · Parse email — one item per email: who sent it, to which address, the text, and
// a list of attachments with the S3 key each will be stored under.
const AUDIO = /\.(m4a|mp3|mp4|wav|flac|ogg|oga|opus|amr|webm|caf|aac|3gp)$/i;
const IMAGE = /\.(jpe?g|png|heic|heif|gif|webp|tiff?)$/i;
const addrList = v => {
  if (!v) return [];
  if (Array.isArray(v)) return v.flatMap(addrList);
  if (typeof v === 'object' && Array.isArray(v.value)) return v.value.map(a => ({ address: String(a.address || '').toLowerCase(), name: a.name || '' }));
  if (typeof v === 'object' && v.address) return [{ address: String(v.address).toLowerCase(), name: v.name || '' }];
  return String(v).split(/[,;]/).map(s => {
    const m = s.match(/^\s*"?([^"<]*?)"?\s*<([^>]+)>\s*$/);
    return m ? { address: m[2].trim().toLowerCase(), name: m[1].trim() } : { address: s.trim().toLowerCase(), name: '' };
  }).filter(a => a.address);
};
const safeName = n => String(n || 'file').normalize('NFKD').replace(/[^\w.\-]+/g, '_').slice(-80) || 'file';

const out = [];
for (const item of $input.all()) {
  const j = item.json;
  const from = addrList(j.from)[0] || { address: '', name: '' };
  const to = [...addrList(j.to), ...addrList(j.cc), ...addrList(j.deliveredTo || j['delivered-to'])];
  const messageId = String(j.messageId || j['message-id'] || '').trim();
  const idHash = crypto.createHash('sha1').update(messageId || JSON.stringify([from.address, j.subject, j.date])).digest('hex').slice(0, 16);
  const box = (to.find(a => /\.inbox@/.test(a.address)) || to[0] || { address: 'unknown' }).address.split('@')[0];
  const attachments = [];
  const binary = {};
  let n = 0;
  for (const [prop, bin] of Object.entries(item.binary || {})) {
    n += 1;
    const name = bin.fileName || `${prop}.${bin.fileExtension || 'bin'}`;
    const mime = bin.mimeType || '';
    const kind = mime.startsWith('audio/') || AUDIO.test(name) ? 'audio'
               : mime.startsWith('image/') || IMAGE.test(name) ? 'image' : 'file';
    const key = `${box}/${idHash}/${n}-${safeName(name)}`;
    attachments.push({ kind, name, mime, size: bin.fileSize || null, key, prop: `file${n}` });
    binary[`file${n}`] = bin;
  }
  let text = String(j.text || j.textPlain || '').replace(/\r\n/g, '\n').trim();
  if (text.length > 20000) text = text.slice(0, 20000);
  out.push({
    json: {
      messageId,
      to: to.map(a => a.address).join(', '),
      fromEmail: from.address,
      fromName: from.name,
      subject: String(j.subject || '').slice(0, 300),
      text,
      attachments
    },
    binary
  });
}
return out;
