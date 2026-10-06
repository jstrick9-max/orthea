// Orthea Consult — letter renderer (PDF + Word) for approved letters.
//
// Dependency-free on purpose: this file is pasted verbatim into the n8n Code node of
// "C02 Consult - Download Letter", where only plain JavaScript and Buffer are
// guaranteed. No require(), no zlib: the .docx is a stored (uncompressed) zip and
// the PDF passes the PNG letterhead data through untouched.
//
// Layout follows letterhead/letterhead.html: US Letter, 0.85in side margins,
// letterhead header on page 1, address footer on every page, 10.5pt body text
// with 1.6 line height and 10pt between paragraphs.

// ---------------------------------------------------------------- letter text

// Mirrors the formatting in the Budibase query "C · Consult review": every line is
// its own paragraph, except that a "Thanks," / "Best," line keeps the line after it
// in the same paragraph (so the sign-off stays together).
function letterParagraphs(text) {
  const lines = String(text == null ? '' : text)
    .replace(/\\n/g, '\n')
    .replace(/\r\n?/g, '\n')
    .split('\n')
    .map(l => l.trim())
    .filter(l => l !== '');
  const paras = [];
  for (const line of lines) {
    const cur = paras[paras.length - 1];
    if (cur && /(Thanks,|Best,)$/.test(cur[cur.length - 1])) cur.push(line);
    else paras.push([line]);
  }
  return paras;
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

// ---------------------------------------------------------------- PDF

// Helvetica advance widths (1/1000 em) for WinAnsi codes 32–126 and 160–255.
const HELV_ASCII = [278,278,355,556,556,889,667,191,333,333,389,584,278,333,278,278,556,556,556,556,556,556,556,556,556,556,278,278,584,584,584,556,1015,667,667,722,722,667,611,778,722,278,500,667,556,833,722,778,667,778,722,667,611,722,667,944,667,667,611,278,278,278,469,556,333,556,556,500,556,556,278,556,556,222,222,500,222,833,556,556,556,556,333,500,278,556,500,722,500,500,500,334,260,334,584];
const HELV_HIGH = [278,333,556,556,556,556,260,556,333,737,370,556,584,333,737,333,400,584,333,333,333,556,537,278,333,333,365,556,834,834,834,611,667,667,667,667,667,667,1000,722,667,667,667,667,278,278,278,278,722,722,778,778,778,778,778,584,778,722,722,722,722,667,667,611,556,556,556,556,556,556,889,500,556,556,556,556,278,278,278,278,556,556,556,556,556,556,556,584,611,556,556,556,556,500,556,500];
// Unicode → WinAnsi for the 128–159 block (curly quotes, dashes, ellipsis, …).
const WINANSI_SPECIAL = {8364:128,8218:130,402:131,8222:132,8230:133,8224:134,8225:135,710:136,8240:137,352:138,8249:139,338:140,381:142,8216:145,8217:146,8220:147,8221:148,8226:149,8211:150,8212:151,732:152,8482:153,353:154,8250:155,339:156,382:158,376:159};
const HELV_SPECIAL = {128:556,130:222,131:556,132:333,133:1000,134:556,135:556,136:333,137:1000,138:667,139:333,140:1000,142:611,145:222,146:222,147:333,148:333,149:350,150:556,151:1000,152:333,153:1000,154:500,155:333,156:944,158:500,159:667};

function winAnsiCodes(str) {
  const out = [];
  for (const ch of String(str).normalize('NFC')) {
    const cp = ch.codePointAt(0);
    if (cp >= 32 && cp <= 126) out.push(cp);
    else if (cp >= 160 && cp <= 255) out.push(cp);
    else if (WINANSI_SPECIAL[cp]) out.push(WINANSI_SPECIAL[cp]);
    else if (cp === 9) out.push(32);
    else if (cp === 8203 || cp === 65279) continue; // zero-width space / BOM
    else out.push(63); // '?'
  }
  return out;
}

function codeWidth(c) {
  if (c >= 32 && c <= 126) return HELV_ASCII[c - 32];
  if (c >= 160) return HELV_HIGH[c - 160];
  return HELV_SPECIAL[c] || 556;
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
const BODY_SIZE = 10.5, LEADING = BODY_SIZE * 1.6, PARA_GAP = 10;
const HEADER_GAP = 0.55 * PT;                       // letterhead main padding-top
const DATE_GAP = 18;                                // space under the date line
const FOOTER_GAP = 24;                              // body must stop this far above the footer
const INK = '0.239 0.220 0.212';                    // #3D3836

function buildPdf({ paragraphs, dateLine, header, footer, title }) {
  const hdr = parsePng(header), ftr = parsePng(footer);
  const hdrH = CONTENT_W * hdr.height / hdr.width;
  const ftrH = CONTENT_W * ftr.height / ftr.width;
  const bodyBottom = MARGIN_BOTTOM + ftrH + FOOTER_GAP;

  // Lay text out into pages. y is the baseline of the next line.
  const pages = [[]];
  let y = PAGE_H - MARGIN_TOP - hdrH - HEADER_GAP - BODY_SIZE;
  const newPage = () => { pages.push([]); y = PAGE_H - MARGIN_TOP - BODY_SIZE; };
  const place = (text) => {
    if (y < bodyBottom) newPage();
    pages[pages.length - 1].push({ text, y });
    y -= LEADING;
  };
  if (dateLine) { place(dateLine); y -= DATE_GAP; }
  paragraphs.forEach((para, i) => {
    const lines = para.flatMap(l => wrapLine(l, BODY_SIZE, CONTENT_W));
    // Keep short paragraphs (the sign-off) together on one page.
    if (lines.length <= 4 && y - (lines.length - 1) * LEADING < bodyBottom) newPage();
    lines.forEach(place);
    if (i < paragraphs.length - 1) y -= PARA_GAP;
  });

  // Objects: 1 catalog, 2 pages, 3 font, 4 header image, 5 footer image, 6 info,
  // then a page + content stream pair per page.
  const objs = [];
  const pageIds = pages.map((_, i) => 7 + i * 2);
  objs[1] = '<< /Type /Catalog /Pages 2 0 R >>';
  objs[2] = `<< /Type /Pages /Kids [${pageIds.map(id => id + ' 0 R').join(' ')}] /Count ${pages.length} >>`;
  objs[3] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>';
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
    ops.push(`BT /F1 ${BODY_SIZE} Tf ${INK} rg`);
    for (const l of lines) ops.push(`1 0 0 1 ${MARGIN_X.toFixed(2)} ${l.y.toFixed(2)} Tm ${pdfString(l.text)} Tj`);
    ops.push('ET');
    const stream = Buffer.from(ops.join('\n'), 'latin1');
    objs[pageIds[i]] = `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${PAGE_W} ${PAGE_H}] ` +
      `/Resources << /Font << /F1 3 0 R >> /XObject << /Im1 4 0 R /Im2 5 0 R >> >> ` +
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

const RUN_PR = '<w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:color w:val="3D3836"/><w:sz w:val="21"/><w:szCs w:val="21"/></w:rPr>';

function docxParagraph(lines, afterTwips) {
  const runs = lines.map((l, i) =>
    (i ? `<w:r>${RUN_PR}<w:br/></w:r>` : '') +
    `<w:r>${RUN_PR}<w:t xml:space="preserve">${xmlEscape(l)}</w:t></w:r>`).join('');
  return `<w:p><w:pPr><w:keepLines/><w:spacing w:before="0" w:after="${afterTwips}" w:line="384" w:lineRule="auto"/></w:pPr>${runs}</w:p>`;
}

function buildDocx({ paragraphs, dateLine, header, footer, title }) {
  const hdr = parsePng(header), ftr = parsePng(footer);
  const hdrH = CONTENT_W * hdr.height / hdr.width;
  const ftrH = CONTENT_W * ftr.height / ftr.width;

  const body = [];
  if (dateLine) body.push(docxParagraph([dateLine], Math.round((PARA_GAP + DATE_GAP) * TWIP)));
  paragraphs.forEach(p => body.push(docxParagraph(p, PARA_GAP * TWIP)));

  // Page 1 uses the letterhead as a first-page header; a spacer paragraph under it
  // pushes the body down by the letterhead's 0.55in gap. Later pages have no header.
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
    `<w:document ${NS}><w:body>${body.join('')}${sect}</w:body></w:document>`;

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

  return zipStore([
    { name: '[Content_Types].xml', data: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n` +
      `<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">` +
      `<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>` +
      `<Default Extension="xml" ContentType="application/xml"/>` +
      `<Default Extension="png" ContentType="image/png"/>` +
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
      ['rIdFtrFirst', 'officeDocument/2006/relationships/footer', 'footer2.xml']]) },
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
  ]);
}

// @export-start (removed when pasted into n8n)
module.exports = { letterParagraphs, buildPdf, buildDocx, textWidth, wrapLine, zipStore, crc32 };
// @export-end
