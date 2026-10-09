// ---------------------------------------------------------------- C02 Code node
// Input: one row from "Load approved letter". Output: the file as binary "data",
// plus the audit-log fields for "Log download".

const HEADER_PNG = Buffer.from('__HEADER_PNG_BASE64__', 'base64');
const FOOTER_PNG = Buffer.from('__FOOTER_PNG_BASE64__', 'base64');

const row = $input.first().json;
const req = $('Download requested').first().json;
const format = row.format === 'docx' ? 'docx' : 'pdf';

const kind = row.output_type === 'family_letter' ? 'Family Letter' : 'Doctor Letter';
const patient = [row.first_name, row.last_name].filter(Boolean).join(' ');
const safe = s => String(s).replace(/[^A-Za-z0-9 .,'()-]/g, '').replace(/\s+/g, ' ').trim();
const filename = safe(`${patient} - ${kind}`) + '.' + format;

const doc = {
  // Family letters carry the composite photo after the first paragraph, when there is one.
  blocks: withComposite(letterBlocks(row.letter_text),
                        row.output_type === 'family_letter' ? loadImage(row.composite_image) : null),
  dateLine: row.letter_date,
  header: HEADER_PNG,
  footer: FOOTER_PNG,
  title: `${patient} - ${kind}`,
};
const file = format === 'docx' ? buildDocx(doc) : buildPdf(doc);
const mime = format === 'docx'
  ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  : 'application/pdf';

const by = req.query && req.query.by ? String(req.query.by).trim().toLowerCase().slice(0, 200) : '';

return [{
  json: {
    consult_id: String(row.consult_id),
    action: `downloaded ${row.output_type} ${format}`,
    actor: by || 'download link',
    filename,
    mime,
  },
  binary: {
    data: this.helpers && this.helpers.prepareBinaryData
      ? await this.helpers.prepareBinaryData(file, filename, mime)
      : { data: file.toString('base64'), mimeType: mime, fileName: filename, fileExtension: format },
  },
}];
