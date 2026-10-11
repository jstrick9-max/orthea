// E01 · Plan uploads — one item per attachment of each newly stored (not held, not duplicate)
// message, signed for S3. A message without attachments gives one "nothing to upload" item.
const parsed = $('Parse email').all();
const out = [];
for (const r of $input.all()) {
  const res = r.json;
  if (!res.item_id || res.status !== 'processing' || res.duplicate === true || res.duplicate === 't') continue;
  const src = parsed.find(p => p.json.messageId === res.message_id) || parsed[0];
  const atts = src.json.attachments || [];
  if (!atts.length) { out.push({ json: { itemId: res.item_id, upload: false } }); continue; }
  for (const a of atts) {
    const host = `${BUCKET}.s3.${AWS_REGION}.amazonaws.com`;
    const s = awsSign({
      method: 'PUT', host, path: s3Path(a.key), service: 's3', payloadHash: 'UNSIGNED-PAYLOAD',
      headers: { 'x-amz-content-sha256': 'UNSIGNED-PAYLOAD', 'x-amz-server-side-encryption': 'AES256' }
    });
    out.push({
      json: { itemId: res.item_id, upload: true, key: a.key, url: s.url, h: s.headers },
      binary: { file: src.binary[a.prop] }
    });
  }
}
return out;
