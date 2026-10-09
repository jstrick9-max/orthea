// Orthea Consult — letter renderer (PDF + Word) for approved letters.
//
// Dependency-free on purpose: this file is pasted verbatim into the n8n Code node of
// "C02 Consult - Download Letter", where only plain JavaScript and Buffer are
// guaranteed. No require(), no zlib: the .docx is a stored (uncompressed) zip and
// the PDF passes the PNG letterhead data through untouched.
//
// Layout follows LSO's own Dolphin consultation letters: US Letter, 0.85in side
// margins, letterhead header on page 1, address footer on every page, Times 11.5pt
// body, underlined section headings, bullet and numbered lists with a hanging indent,
// and the mailing address and sign-off set as tight single-spaced blocks.

// ---------------------------------------------------------------- letter structure

// Section headings used by the letter templates. A short Title Case line with no
// end punctuation is also treated as a heading, so practice-edited templates work.
const HEADINGS = new Set([
  'dental relationships', 'skeletal and facial relationships', 'radiographic findings',
  'treatment plan', 'long-term considerations', 'special considerations', 'fees',
]);
const SMALL_WORDS = new Set(['and', 'of', 'the', 'to', 'for', 'a', 'an', 'in', 'on', 'or', 'with']);
const GREETING_RE = /^(Hi|Dear|Hello)\s.+,$/;
const SIGNOFF_RE = /^(Thanks|Thank you|Best|Sincerely|Regards|Warm regards|Kind regards),$/i;
const BULLET_RE = /^[•●*-]\s+/;
const NUMBER_RE = /^(\d+)[.)]\s+/;

function isHeading(line) {
  if (HEADINGS.has(line.toLowerCase())) return true;
  if (/[.,:;!?]$/.test(line) || line.length > 45) return false;
  const words = line.split(/\s+/);
  return words.length <= 5 && words.every(w => SMALL_WORDS.has(w) || /^[A-Z][A-Za-z'-]*$/.test(w));
}

// Turns the letter text into blocks:
//   { kind: 'tight',   lines: [...] }      address / sign-off, single-spaced
//   { kind: 'para',    text, keepNext }    ordinary paragraph (keepNext when it ends in ':')
//   { kind: 'heading', text }
//   { kind: 'list',    items: [{ marker, text }] }
// Blank lines are ignored, so letters edited on the review screen (where every line
// is shown as its own paragraph) come out the same.
function letterBlocks(text) {
  const lines = String(text == null ? '' : text)
    .replace(/\\n/g, '\n')
    .replace(/\r\n?/g, '\n')
    .split('\n')
    .map(l => l.trim())
    .filter(l => l !== '');

  const greeting = lines.findIndex(l => GREETING_RE.test(l));
  let signoff = -1;
  for (let i = Math.max(greeting + 1, lines.length - 6); i < lines.length; i++) {
    if (SIGNOFF_RE.test(lines[i])) { signoff = i; break; }
  }

  const blocks = [];
  let start = 0;
  if (greeting > 0) { blocks.push({ kind: 'tight', lines: lines.slice(0, greeting) }); start = greeting; }
  const end = signoff >= 0 ? signoff : lines.length;

  for (let i = start; i < end; i++) {
    const line = lines[i];
    const prev = blocks[blocks.length - 1];
    const b = line.match(BULLET_RE);
    const n = line.match(NUMBER_RE);
    if (b || n) {
      const item = { marker: b ? '•' : n[1] + '.', text: line.slice((b || n)[0].length) };
      if (prev && prev.kind === 'list') prev.items.push(item);
      else blocks.push({ kind: 'list', items: [item] });
    } else if (i !== greeting && isHeading(line)) {
      blocks.push({ kind: 'heading', text: line });
    } else {
      blocks.push({ kind: 'para', text: line, keepNext: /:$/.test(line) });
    }
  }
  if (signoff >= 0) blocks.push({ kind: 'tight', lines: lines.slice(signoff), keepTogether: true });
  return blocks;
}

// ---------------------------------------------------------------- binary helpers

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

// Zip with every entry stored (method 0). Word, Google Docs and LibreOffice all
// open stored .docx files; they are only somewhat larger than deflated ones.
function zipStore(files) {
  const chunks = [];
  const central = [];
  let offset = 0;
  const dosTime = 0;            // 00:00:00
  const dosDate = (46 << 9) | (1 << 5) | 1; // 2026-01-01; zip dates are cosmetic here
  for (const f of files) {
    const name = Buffer.from(f.name, 'utf8');
    const data = Buffer.isBuffer(f.data) ? f.data : Buffer.from(f.data, 'utf8');
    const crc = crc32(data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);       // version needed
    local.writeUInt16LE(0x0800, 6);   // UTF-8 names
    local.writeUInt16LE(0, 8);        // stored
    local.writeUInt16LE(dosTime, 10);
    local.writeUInt16LE(dosDate, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(data.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(name.length, 26);
    local.writeUInt16LE(0, 28);
    chunks.push(local, name, data);

    const cen = Buffer.alloc(46);
    cen.writeUInt32LE(0x02014b50, 0);
    cen.writeUInt16LE(20, 4);
    cen.writeUInt16LE(20, 6);
    cen.writeUInt16LE(0x0800, 8);
    cen.writeUInt16LE(0, 10);
    cen.writeUInt16LE(dosTime, 12);
    cen.writeUInt16LE(dosDate, 14);
    cen.writeUInt32LE(crc, 16);
    cen.writeUInt32LE(data.length, 20);
    cen.writeUInt32LE(data.length, 24);
    cen.writeUInt16LE(name.length, 28);
    cen.writeUInt32LE(offset, 42);
    central.push(cen, name);
    offset += local.length + name.length + data.length;
  }
  const cenBuf = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(files.length, 8);
  end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(cenBuf.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...chunks, cenBuf, end]);
}

// Reads an 8-bit RGB, non-interlaced PNG — the format render-letterhead.mjs writes.
function parsePng(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error('Letterhead image is not a PNG');
  let pos = 8;
  let width, height, bitDepth, colorType, interlace;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString('latin1', pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      interlace = data[12];
    } else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
    pos += 12 + len;
  }
  if (bitDepth !== 8 || colorType !== 2 || interlace !== 0) {
    throw new Error('Letterhead PNG must be 8-bit RGB, non-interlaced');
  }
  return { width, height, data: Buffer.concat(idat), png: buf };
}


// ---------------------------------------------------------------- composite photo

// Reads the composite photo stored in consults.composite_image (base64, JPEG or PNG).
// Returns { format, width, height, bytes } or null if it isn't a usable image.
function loadImage(base64) {
  if (!base64) return null;
  const buf = Buffer.from(String(base64).replace(/^data:[^,]*,/, ''), 'base64');
  if (buf.length > 4 && buf[0] === 0xff && buf[1] === 0xd8) {
    // JPEG: size and colour channels come from the first SOF marker.
    let pos = 2;
    while (pos + 9 < buf.length) {
      if (buf[pos] !== 0xff) { pos++; continue; }
      const marker = buf[pos + 1];
      if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) { pos += 2; continue; }
      const len = buf.readUInt16BE(pos + 2);
      if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
        return { format: 'jpeg', height: buf.readUInt16BE(pos + 5), width: buf.readUInt16BE(pos + 7),
                 components: buf[pos + 9], bytes: buf };
      }
      pos += 2 + len;
    }
    return null;
  }
  if (buf.length > 24 && buf.readUInt32BE(0) === 0x89504e47) {
    return { format: 'png', width: buf.readUInt32BE(16), height: buf.readUInt32BE(20),
             bitDepth: buf[24], colorType: buf[25], interlace: buf[28], bytes: buf };
  }
  return null;
}

// Family letters: the photo goes straight after the first paragraph below the greeting.
function withComposite(blocks, image) {
  if (!image) return blocks;
  const greeting = blocks.findIndex(b => b.kind === 'para' && GREETING_RE.test(b.text));
  let at = blocks.findIndex((b, i) => i > greeting && b.kind === 'para');
  if (at < 0) at = greeting;
  const out = blocks.slice();
  out.splice(at + 1, 0, { kind: 'image', image });
  return out;
}

// Largest size that fits the text column and the height cap, keeping proportions.
const PHOTO_MAX_H = 3.6 * 72;                       // photo height cap (3.6in)
function photoSize(img, maxW) {
  const s = Math.min(maxW / img.width, PHOTO_MAX_H / img.height);
  return { w: img.width * s, h: img.height * s };
}

// PDF image object for the photo, or null if this PNG variant can't be embedded.
// JPEGs pass through untouched. 8-bit RGB / grey PNGs pass through with a predictor.
// Other PNGs (alpha, palette, 1–16 bit) are decoded and flattened onto white, which needs zlib;
// if the Code node can't load it the photo is left out of the PDF (Word still has it).
function pdfImage(img) {
  if (img.format === 'jpeg') {
    const cs = img.components === 1 ? '/DeviceGray' : img.components === 4 ? '/DeviceCMYK /Decode [1 0 1 0 1 0 1 0]' : '/DeviceRGB';
    return [`<< /Type /XObject /Subtype /Image /Width ${img.width} /Height ${img.height} ` +
            `/ColorSpace ${cs} /BitsPerComponent 8 /Filter /DCTDecode /Length ${img.bytes.length} >>`, img.bytes];
  }
  const chunks = [];
  let palette = null, pos = 8;
  while (pos < img.bytes.length) {
    const len = img.bytes.readUInt32BE(pos), type = img.bytes.toString('latin1', pos + 4, pos + 8);
    const data = img.bytes.subarray(pos + 8, pos + 8 + len);
    if (type === 'IDAT') chunks.push(data);
    else if (type === 'PLTE') palette = data;
    else if (type === 'IEND') break;
    pos += 12 + len;
  }
  const idat = Buffer.concat(chunks);
  if (img.bitDepth === 8 && img.interlace === 0 && (img.colorType === 2 || img.colorType === 0)) {
    const colors = img.colorType === 2 ? 3 : 1;
    return [`<< /Type /XObject /Subtype /Image /Width ${img.width} /Height ${img.height} ` +
            `/ColorSpace /Device${colors === 3 ? 'RGB' : 'Gray'} /BitsPerComponent 8 /Filter /FlateDecode ` +
            `/DecodeParms << /Predictor 15 /Colors ${colors} /BitsPerComponent 8 /Columns ${img.width} >> ` +
            `/Length ${idat.length} >>`, idat];
  }
  if (img.interlace !== 0 || ![0, 2, 3, 4, 6].includes(img.colorType)) return null;
  let zlib;
  try { zlib = require('zlib'); } catch (e) { return null; }
  // Decode any non-interlaced PNG (1–16 bit, grey / RGB / palette, with or without
  // alpha) to 8-bit RGB, flattening transparency onto white.
  const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[img.colorType];
  const bd = img.bitDepth, bitsPx = channels * bd;
  const stride = Math.ceil(img.width * bitsPx / 8), fbpp = Math.max(1, bitsPx >> 3);
  const raw = zlib.inflateSync(idat);
  const rgb = Buffer.alloc(img.width * img.height * 3);
  const max = (1 << Math.min(bd, 8)) - 1;
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < img.height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = Buffer.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let x = 0; x < stride; x++) {
      const a = x >= fbpp ? line[x - fbpp] : 0, b = prev[x], c = x >= fbpp ? prev[x - fbpp] : 0;
      let p = 0;
      if (filter === 1) p = a;
      else if (filter === 2) p = b;
      else if (filter === 3) p = (a + b) >> 1;
      else if (filter === 4) { const pa = Math.abs(b - c), pb = Math.abs(a - c), pc = Math.abs(a + b - 2 * c); p = pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      line[x] = (line[x] + p) & 0xff;
    }
    // sample(x, ch): channel value scaled to 0–255 (palette index left as is)
    const sample = (x, ch) => {
      const i = x * channels + ch;
      if (bd === 8) return line[i];
      if (bd === 16) return line[i * 2];
      const v = (line[(i * bd) >> 3] >> (8 - bd - ((i * bd) & 7))) & max;
      return img.colorType === 3 ? v : Math.round(v * 255 / max);
    };
    for (let x = 0; x < img.width; x++) {
      let r, g, bl, al = 255;
      if (img.colorType === 3) { const i = sample(x, 0) * 3; r = palette[i]; g = palette[i + 1]; bl = palette[i + 2]; }
      else if (img.colorType === 0) { r = g = bl = sample(x, 0); }
      else if (img.colorType === 4) { r = g = bl = sample(x, 0); al = sample(x, 1); }
      else { r = sample(x, 0); g = sample(x, 1); bl = sample(x, 2); if (img.colorType === 6) al = sample(x, 3); }
      const o = (y * img.width + x) * 3, k = al / 255;
      rgb[o] = Math.round(r * k + 255 * (1 - k)); rgb[o + 1] = Math.round(g * k + 255 * (1 - k)); rgb[o + 2] = Math.round(bl * k + 255 * (1 - k));
    }
    prev = line;
  }
  const data = zlib.deflateSync(rgb);
  return [`<< /Type /XObject /Subtype /Image /Width ${img.width} /Height ${img.height} ` +
          `/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length ${data.length} >>`, data];
}

// ---------------------------------------------------------------- PDF

// Times-Roman advance widths (1/1000 em) for WinAnsi codes 32–126, 160–255 and 128–159.
const TIMES_ASCII = [250,333,408,500,500,833,778,180,333,333,500,564,250,333,250,278,500,500,500,500,500,500,500,500,500,500,278,278,564,564,564,444,921,722,667,667,722,611,556,722,722,333,389,722,611,889,722,722,556,722,667,556,611,722,722,944,722,722,611,333,278,333,469,500,333,444,500,444,500,444,333,500,500,278,278,500,278,778,500,500,500,500,333,389,278,500,500,722,500,500,444,480,200,480,541];
const TIMES_HIGH = [250,333,500,500,500,500,200,500,333,760,276,500,564,333,760,333,400,564,300,300,333,500,453,250,333,300,310,500,750,750,750,444,722,722,722,722,722,722,889,667,611,611,611,611,333,333,333,333,722,722,722,722,722,722,722,564,722,722,722,722,722,722,556,500,444,444,444,444,444,444,667,444,444,444,444,444,278,278,278,278,500,500,500,500,500,500,500,564,500,500,500,500,500,500,500,500];
const TIMES_SPECIAL = {128:500,129:350,130:333,131:500,132:444,133:1000,134:500,135:500,136:333,137:1000,138:556,139:333,140:889,141:350,142:611,143:350,144:350,145:333,146:333,147:444,148:444,149:350,150:500,151:1000,152:333,153:980,154:389,155:333,156:722,157:350,158:444,159:722};
// Unicode → WinAnsi for the 128–159 block (curly quotes, dashes, ellipsis, bullet, …).
const WINANSI_SPECIAL = {8364:128,8218:130,402:131,8222:132,8230:133,8224:134,8225:135,710:136,8240:137,352:138,8249:139,338:140,381:142,8216:145,8217:146,8220:147,8221:148,8226:149,8211:150,8212:151,732:152,8482:153,353:154,8250:155,339:156,382:158,376:159};

function winAnsiCodes(str) {
  const out = [];
  for (const ch of String(str).normalize('NFC')) {
    const cp = ch.codePointAt(0);
    if (cp >= 32 && cp <= 126) out.push(cp);
    else if (cp >= 160 && cp <= 255) out.push(cp);
    else if (WINANSI_SPECIAL[cp]) out.push(WINANSI_SPECIAL[cp]);
    else if (cp === 9) out.push(32);
    else if (cp === 8203 || cp === 65279) continue; // zero-width space / BOM
    else if (cp === 8594) { out.push(45, 62); }     // → prints as ->
    else out.push(63); // '?'
  }
  return out;
}

function codeWidth(c) {
  if (c >= 32 && c <= 126) return TIMES_ASCII[c - 32];
  if (c >= 160) return TIMES_HIGH[c - 160];
  return TIMES_SPECIAL[c] || 500;
}

function textWidth(str, size) {
  return winAnsiCodes(str).reduce((w, c) => w + codeWidth(c), 0) * size / 1000;
}

function wrapLine(line, size, maxWidth) {
  const words = line.split(/\s+/).filter(Boolean);
  const out = [];
  let cur = '';
  for (const w of words) {
    const next = cur ? cur + ' ' + w : w;
    if (!cur || textWidth(next, size) <= maxWidth) { cur = next; continue; }
    out.push(cur);
    cur = w;
  }
  if (cur) out.push(cur);
  return out.length ? out : [''];
}

function pdfString(str) {
  let s = '(';
  for (const c of winAnsiCodes(str)) {
    if (c === 40 || c === 41 || c === 92) s += '\\' + String.fromCharCode(c);
    else if (c < 128) s += String.fromCharCode(c);
    else s += '\\' + c.toString(8).padStart(3, '0');
  }
  return s + ')';
}

const PT = 72;
const PAGE_W = 8.5 * PT, PAGE_H = 11 * PT;
const MARGIN_X = 0.85 * PT, MARGIN_TOP = 0.7 * PT, MARGIN_BOTTOM = 0.6 * PT;
const CONTENT_W = PAGE_W - 2 * MARGIN_X;            // 6.8in — the width the PNGs were rendered at
const BODY_SIZE = 11.5, LEADING = BODY_SIZE * 1.3;
const PARA_GAP = 9;                                 // between paragraphs
const HEADING_BEFORE = 6, HEADING_AFTER = 3;        // extra space around section headings
const ITEM_GAP = 1.5;                               // between list items
const MARKER_X = 0.25 * PT, ITEM_X = 0.5 * PT;      // list marker and text indents
const HEADER_GAP = 0.45 * PT;                       // space under the letterhead
const DATE_GAP = 14;                                // extra space under the date line
const FOOTER_GAP = 24;                              // body must stop this far above the footer
const INK = '0.122 0.114 0.106';                    // #1F1D1B

// Lays the blocks out as positioned lines: { x, y, text, underline }.
function layoutPdf(blocks, dateLine, firstTop, bodyBottom) {
  const pages = [[]];
  let y = firstTop;
  const newPage = () => { pages.push([]); y = PAGE_H - MARGIN_TOP - BODY_SIZE; };
  // Room for n more lines on this page; `slack` covers the small gaps between them.
  const room = (n, slack = 0) => y - (n - 1) * LEADING - slack >= bodyBottom;
  const put = (text, x, underline) => {
    if (y < bodyBottom) newPage();
    pages[pages.length - 1].push({ text, x, y, underline: !!underline });
    y -= LEADING;
  };
  const wrapPara = (t) => wrapLine(t, BODY_SIZE, CONTENT_W);
  const wrapItem = (t) => wrapLine(t, BODY_SIZE, CONTENT_W - ITEM_X);
  const firstLines = (b) => b ? (b.kind === 'list' ? wrapItem(b.items[0].text).length
                                : b.kind === 'para' ? Math.min(2, wrapPara(b.text).length) : 1) : 0;

  if (dateLine) { put(dateLine, MARGIN_X); y -= DATE_GAP; }

  blocks.forEach((b, i) => {
    const next = blocks[i + 1];
    if (b.kind === 'heading') {
      if (i > 0) y -= HEADING_BEFORE;
      // Keep the heading with the start of what follows it.
      const need = 1 + firstLines(next) + (next && next.keepNext ? firstLines(blocks[i + 2]) : 0);
      if (!room(need, HEADING_AFTER + 2 * ITEM_GAP + PARA_GAP)) newPage();
      put(b.text, MARGIN_X, true);
      y -= HEADING_AFTER;
      return;
    }
    if (b.kind === 'image') {
      // The photo sits on its own, centred; it moves to the next page if it won't fit.
      const { w, h } = photoSize(b.image, CONTENT_W);
      let top = y + BODY_SIZE;
      if (top - h < bodyBottom) { newPage(); top = y + BODY_SIZE; }
      pages[pages.length - 1].push({ image: true, x: MARGIN_X + (CONTENT_W - w) / 2, y: top - h, w, h });
      y = top - h - BODY_SIZE;
      if (i < blocks.length - 1) y -= PARA_GAP;
      return;
    }
    if (b.kind === 'tight') {
      if (b.keepTogether && !room(b.lines.length)) newPage();
      b.lines.forEach(l => wrapPara(l).forEach(w => put(w, MARGIN_X)));
    } else if (b.kind === 'para') {
      const lines = wrapPara(b.text);
      const need = b.keepNext ? lines.length + firstLines(next) : Math.min(lines.length, 2);
      if (!room(need)) newPage();
      lines.forEach(w => put(w, MARGIN_X));
      if (b.keepNext && next && next.kind === 'list') { y -= ITEM_GAP; return; }
    } else if (b.kind === 'list') {
      b.items.forEach((it, k) => {
        const lines = wrapItem(it.text);
        if (!room(Math.min(lines.length, 2))) newPage();
        lines.forEach((w, j) => {
          if (j === 0) {
            if (y < bodyBottom) newPage();
            pages[pages.length - 1].push({ text: it.marker, x: MARGIN_X + MARKER_X, y });
          }
          put(w, MARGIN_X + ITEM_X);
        });
        if (k < b.items.length - 1) y -= ITEM_GAP;
      });
    }
    if (i < blocks.length - 1) y -= PARA_GAP;
  });
  return pages;
}

function buildPdf({ blocks, dateLine, header, footer, title }) {
  const hdr = parsePng(header), ftr = parsePng(footer);
  const hdrH = CONTENT_W * hdr.height / hdr.width;
  const ftrH = CONTENT_W * ftr.height / ftr.width;
  const bodyBottom = MARGIN_BOTTOM + ftrH + FOOTER_GAP;
  // The photo is dropped (not the whole letter) if this PDF can't embed it.
  const photoBlock = blocks.find(b => b.kind === 'image');
  const photoObj = photoBlock ? pdfImage(photoBlock.image) : null;
  if (photoBlock && !photoObj) blocks = blocks.filter(b => b !== photoBlock);
  const pages = layoutPdf(blocks, dateLine, PAGE_H - MARGIN_TOP - hdrH - HEADER_GAP - BODY_SIZE, bodyBottom);

  // Objects: 1 catalog, 2 pages, 3 font, 4 header image, 5 footer image, 6 info,
  // 7 composite photo (only when there is one), then a page + content stream pair per page.
  const objs = [];
  const firstPage = photoObj ? 8 : 7;
  const pageIds = pages.map((_, i) => firstPage + i * 2);
  if (photoObj) objs[7] = photoObj;
  objs[1] = '<< /Type /Catalog /Pages 2 0 R >>';
  objs[2] = `<< /Type /Pages /Kids [${pageIds.map(id => id + ' 0 R').join(' ')}] /Count ${pages.length} >>`;
  objs[3] = '<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman /Encoding /WinAnsiEncoding >>';
  const image = (img) => [
    `<< /Type /XObject /Subtype /Image /Width ${img.width} /Height ${img.height} ` +
    `/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode ` +
    `/DecodeParms << /Predictor 15 /Colors 3 /BitsPerComponent 8 /Columns ${img.width} >> ` +
    `/Length ${img.data.length} >>`, img.data];
  objs[4] = image(hdr);
  objs[5] = image(ftr);
  objs[6] = `<< /Title ${pdfString(title || '')} /Producer (Orthea Consult) >>`;

  pages.forEach((lines, i) => {
    const ops = [];
    if (i === 0) ops.push(`q ${CONTENT_W.toFixed(2)} 0 0 ${hdrH.toFixed(2)} ${MARGIN_X.toFixed(2)} ${(PAGE_H - MARGIN_TOP - hdrH).toFixed(2)} cm /Im1 Do Q`);
    ops.push(`q ${CONTENT_W.toFixed(2)} 0 0 ${ftrH.toFixed(2)} ${MARGIN_X.toFixed(2)} ${MARGIN_BOTTOM.toFixed(2)} cm /Im2 Do Q`);
    for (const p of lines.filter(l => l.image)) {
      ops.push(`q ${p.w.toFixed(2)} 0 0 ${p.h.toFixed(2)} ${p.x.toFixed(2)} ${p.y.toFixed(2)} cm /Im3 Do Q`);
    }
    lines = lines.filter(l => !l.image);
    ops.push(`BT /F1 ${BODY_SIZE} Tf ${INK} rg`);
    for (const l of lines) ops.push(`1 0 0 1 ${l.x.toFixed(2)} ${l.y.toFixed(2)} Tm ${pdfString(l.text)} Tj`);
    ops.push('ET');
    const rules = lines.filter(l => l.underline);
    if (rules.length) {
      ops.push(`${INK} RG 0.6 w`);
      for (const l of rules) {
        const uy = (l.y - 1.8).toFixed(2);
        ops.push(`${l.x.toFixed(2)} ${uy} m ${(l.x + textWidth(l.text, BODY_SIZE)).toFixed(2)} ${uy} l S`);
      }
    }
    const stream = Buffer.from(ops.join('\n'), 'latin1');
    objs[pageIds[i]] = `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${PAGE_W} ${PAGE_H}] ` +
      `/Resources << /Font << /F1 3 0 R >> /XObject << /Im1 4 0 R /Im2 5 0 R${photoObj ? ' /Im3 7 0 R' : ''} >> >> ` +
      `/Contents ${pageIds[i] + 1} 0 R >>`;
    objs[pageIds[i] + 1] = [`<< /Length ${stream.length} >>`, stream];
  });

  const parts = [Buffer.from('%PDF-1.4\n%\xe2\xe3\xcf\xd3\n', 'latin1')];
  let len = parts[0].length;
  const offsets = [];
  for (let id = 1; id < objs.length; id++) {
    offsets[id] = len;
    const o = objs[id];
    const bufs = Array.isArray(o)
      ? [Buffer.from(`${id} 0 obj\n${o[0]}\nstream\n`, 'latin1'), o[1], Buffer.from('\nendstream\nendobj\n', 'latin1')]
      : [Buffer.from(`${id} 0 obj\n${o}\nendobj\n`, 'latin1')];
    for (const b of bufs) { parts.push(b); len += b.length; }
  }
  let xref = `xref\n0 ${objs.length}\n0000000000 65535 f \n`;
  for (let id = 1; id < objs.length; id++) xref += String(offsets[id]).padStart(10, '0') + ' 00000 n \n';
  xref += `trailer\n<< /Size ${objs.length} /Root 1 0 R /Info 6 0 R >>\nstartxref\n${len}\n%%EOF\n`;
  parts.push(Buffer.from(xref, 'latin1'));
  return Buffer.concat(parts);
}

// ---------------------------------------------------------------- Word (.docx)

const TWIP = 20;           // twips per point
const EMU = 12700;         // EMU per point

function xmlEscape(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function drawing(rId, id, name, wPt, hPt) {
  const cx = Math.round(wPt * EMU), cy = Math.round(hPt * EMU);
  return `<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">` +
    `<wp:extent cx="${cx}" cy="${cy}"/><wp:docPr id="${id}" name="${name}"/>` +
    `<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>` +
    `<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">` +
    `<pic:pic><pic:nvPicPr><pic:cNvPr id="${id}" name="${name}"/><pic:cNvPicPr/></pic:nvPicPr>` +
    `<pic:blipFill><a:blip r:embed="${rId}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>` +
    `<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${cx}" cy="${cy}"/></a:xfrm>` +
    `<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>` +
    `</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>`;
}

const NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" ' +
  'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" ' +
  'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" ' +
  'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" ' +
  'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"';

const HALF_PTS = Math.round(BODY_SIZE * 2);
const LINE_240 = Math.round(240 * LEADING / BODY_SIZE / 1.15);   // Word "multiple" spacing close to the PDF
const runPr = (underline) => `<w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>` +
  (underline ? '<w:u w:val="single"/>' : '') +
  `<w:color w:val="1F1D1B"/><w:sz w:val="${HALF_PTS}"/><w:szCs w:val="${HALF_PTS}"/></w:rPr>`;
const run = (text, underline) => `<w:r>${runPr(underline)}<w:t xml:space="preserve">${xmlEscape(text)}</w:t></w:r>`;

function wPara(runs, { before = 0, after = 0, keepNext = false, keepLines = true, ind = '', tabs = '' } = {}) {
  return `<w:p><w:pPr>${keepNext ? '<w:keepNext/>' : ''}${keepLines ? '<w:keepLines/>' : ''}${tabs}` +
    `<w:spacing w:before="${Math.round(before * TWIP)}" w:after="${Math.round(after * TWIP)}" w:line="${LINE_240}" w:lineRule="auto"/>` +
    `${ind}</w:pPr>${runs}</w:p>`;
}

function docxBody(blocks, dateLine) {
  const out = [];
  if (dateLine) out.push(wPara(run(dateLine), { after: PARA_GAP + DATE_GAP }));
  const markerTw = Math.round(MARKER_X * TWIP), itemTw = Math.round(ITEM_X * TWIP);
  blocks.forEach((b, i) => {
    const last = i === blocks.length - 1;
    const next = blocks[i + 1];
    if (b.kind === 'image') {
      const { w, h } = photoSize(b.image, CONTENT_W);
      out.push(`<w:p><w:pPr><w:jc w:val="center"/><w:spacing w:before="0" w:after="${last ? 0 : Math.round(PARA_GAP * TWIP)}" w:line="240" w:lineRule="auto"/></w:pPr>` +
        drawing('rIdPhoto', 4, 'Composite photo', w, h) + `</w:p>`);
    } else if (b.kind === 'heading') {
      out.push(wPara(run(b.text, true), { before: i > 0 ? HEADING_BEFORE : 0, after: HEADING_AFTER, keepNext: true }));
    } else if (b.kind === 'tight') {
      const runs = b.lines.map((l, k) => (k ? `<w:r>${runPr()}<w:br/></w:r>` : '') + run(l)).join('');
      out.push(wPara(runs, { after: last ? 0 : PARA_GAP }));
    } else if (b.kind === 'para') {
      const intoList = b.keepNext && next && next.kind === 'list';
      out.push(wPara(run(b.text), { after: intoList ? ITEM_GAP : (last ? 0 : PARA_GAP), keepNext: b.keepNext }));
    } else if (b.kind === 'list') {
      b.items.forEach((it, k) => {
        const lastItem = k === b.items.length - 1;
        out.push(wPara(run(it.marker) + `<w:r>${runPr()}<w:tab/></w:r>` + run(it.text), {
          after: lastItem ? (last ? 0 : PARA_GAP) : ITEM_GAP,
          tabs: `<w:tabs><w:tab w:val="left" w:pos="${itemTw}"/></w:tabs>`,
          ind: `<w:ind w:left="${itemTw}" w:hanging="${itemTw - markerTw}"/>`,
        }));
      });
    }
  });
  return out.join('');
}

function buildDocx({ blocks, dateLine, header, footer, title }) {
  const hdr = parsePng(header), ftr = parsePng(footer);
  const hdrH = CONTENT_W * hdr.height / hdr.width;
  const ftrH = CONTENT_W * ftr.height / ftr.width;

  // Page 1 uses the letterhead as a first-page header; a spacer paragraph under it
  // pushes the body down by the letterhead gap. Later pages have no header.
  const sect =
    `<w:sectPr>` +
    `<w:headerReference w:type="first" r:id="rIdHdr"/>` +
    `<w:headerReference w:type="default" r:id="rIdHdrBlank"/>` +
    `<w:footerReference w:type="first" r:id="rIdFtrFirst"/>` +
    `<w:footerReference w:type="default" r:id="rIdFtr"/>` +
    `<w:pgSz w:w="12240" w:h="15840"/>` +
    `<w:pgMar w:top="${Math.round(MARGIN_TOP * TWIP)}" w:right="${Math.round(MARGIN_X * TWIP)}" ` +
    `w:bottom="${Math.round((MARGIN_BOTTOM + ftrH + FOOTER_GAP) * TWIP)}" w:left="${Math.round(MARGIN_X * TWIP)}" ` +
    `w:header="${Math.round(MARGIN_TOP * TWIP)}" w:footer="${Math.round(MARGIN_BOTTOM * TWIP)}" w:gutter="0"/>` +
    `<w:titlePg/>` +
    `</w:sectPr>`;

  const documentXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n` +
    `<w:document ${NS}><w:body>${docxBody(blocks, dateLine)}${sect}</w:body></w:document>`;

  const zero = '<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>';
  const headerXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n` +
    `<w:hdr ${NS}>` +
    `<w:p><w:pPr>${zero}</w:pPr>${drawing('rIdImg', 1, 'Letterhead', CONTENT_W, hdrH)}</w:p>` +
    `<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="${Math.round(HEADER_GAP * TWIP)}" w:lineRule="exact"/></w:pPr></w:p>` +
    `</w:hdr>`;
  const blankHeaderXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n` +
    `<w:hdr ${NS}><w:p><w:pPr>${zero}</w:pPr></w:p></w:hdr>`;
  // Word expects one part per footer reference, so page 1 and later pages each get a copy.
  const footerXml = (id) => `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n` +
    `<w:ftr ${NS}><w:p><w:pPr>${zero}</w:pPr>${drawing('rIdImg', id, 'Letterhead footer', CONTENT_W, ftrH)}</w:p></w:ftr>`;

  const rels = (items) => `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n` +
    `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` +
    items.map(([id, type, target]) =>
      `<Relationship Id="${id}" Type="http://schemas.openxmlformats.org/${type}" Target="${target}"/>`).join('') +
    `</Relationships>`;
  const now = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');

  const photo = (blocks.find(b => b.kind === 'image') || {}).image;
  const photoName = photo ? 'media/composite.' + (photo.format === 'jpeg' ? 'jpg' : 'png') : null;
  return zipStore([
    { name: '[Content_Types].xml', data: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n` +
      `<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">` +
      `<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>` +
      `<Default Extension="xml" ContentType="application/xml"/>` +
      `<Default Extension="png" ContentType="image/png"/>` +
      `<Default Extension="jpg" ContentType="image/jpeg"/>` +
      `<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>` +
      `<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>` +
      `<Override PartName="/word/header2.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>` +
      `<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>` +
      `<Override PartName="/word/footer2.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>` +
      `<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>` +
      `</Types>` },
    { name: '_rels/.rels', data: rels([
      ['rId1', 'officeDocument/2006/relationships/officeDocument', 'word/document.xml'],
      ['rId2', 'package/2006/relationships/metadata/core-properties', 'docProps/core.xml']]) },
    { name: 'docProps/core.xml', data: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n` +
      `<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" ` +
      `xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" ` +
      `xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">` +
      `<dc:title>${xmlEscape(title || '')}</dc:title><dc:creator>Orthea Consult</dc:creator>` +
      `<dcterms:created xsi:type="dcterms:W3CDTF">${now}</dcterms:created>` +
      `</cp:coreProperties>` },
    { name: 'word/document.xml', data: documentXml },
    { name: 'word/_rels/document.xml.rels', data: rels([
      ['rIdHdr', 'officeDocument/2006/relationships/header', 'header1.xml'],
      ['rIdHdrBlank', 'officeDocument/2006/relationships/header', 'header2.xml'],
      ['rIdFtr', 'officeDocument/2006/relationships/footer', 'footer1.xml'],
      ['rIdFtrFirst', 'officeDocument/2006/relationships/footer', 'footer2.xml'],
      ...(photo ? [['rIdPhoto', 'officeDocument/2006/relationships/image', photoName]] : [])]) },
    { name: 'word/header1.xml', data: headerXml },
    { name: 'word/_rels/header1.xml.rels', data: rels([
      ['rIdImg', 'officeDocument/2006/relationships/image', 'media/header.png']]) },
    { name: 'word/header2.xml', data: blankHeaderXml },
    { name: 'word/footer1.xml', data: footerXml(2) },
    { name: 'word/_rels/footer1.xml.rels', data: rels([
      ['rIdImg', 'officeDocument/2006/relationships/image', 'media/footer.png']]) },
    { name: 'word/footer2.xml', data: footerXml(3) },
    { name: 'word/_rels/footer2.xml.rels', data: rels([
      ['rIdImg', 'officeDocument/2006/relationships/image', 'media/footer.png']]) },
    { name: 'word/media/header.png', data: hdr.png },
    { name: 'word/media/footer.png', data: ftr.png },
    ...(photo ? [{ name: 'word/' + photoName, data: photo.bytes }] : []),
  ]);
}

// @export-start (removed when pasted into n8n)
module.exports = { letterBlocks, loadImage, withComposite, pdfImage, buildPdf, buildDocx, textWidth, wrapLine, zipStore, crc32 };
// @export-end
