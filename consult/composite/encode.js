// C03 · Encode — check the download is a JPEG/PNG and convert it to base64 for
// consults.composite_image (the format /review and the C02 downloads read).
const MAX_BYTES = 15 * 1024 * 1024;
const buf = await this.helpers.getBinaryDataBuffer(0, 'data');
const isJpeg = buf.length > 3 && buf[0] === 0xff && buf[1] === 0xd8;
const isPng = buf.length > 8 && buf.readUInt32BE(0) === 0x89504e47;
if (!isJpeg && !isPng) throw new Error(`Composite is not a JPEG or PNG (${buf.length} bytes)`);
if (buf.length > MAX_BYTES) throw new Error(`Composite is too large (${buf.length} bytes)`);
const src = $('Build URL').first().json;
return [{ json: { id: src.id, source: src.source, image: buf.toString('base64') } }];
