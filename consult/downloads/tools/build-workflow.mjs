// Builds the importable n8n workflow "C02 Consult - Download Letter".
//
//   node consult/downloads/tools/build-workflow.mjs
//
// Inlines src/render.js + src/code-node.js (with the letterhead PNGs as base64)
// into the Code node and writes ../C02_Consult_-_Download_Letter.json.

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (p) => readFileSync(path.join(root, p));

// Fixed so the production URL is known before import:
//   https://listen.ortheasecurity.com/webhook/<WEBHOOK_ID>/consult/letter/<token>/<doctor|family>/<pdf|docx>
export const WEBHOOK_ID = '7c3f9a52-4e1d-4b8a-9f6e-2d5c8b1a0e47';

const CONSULT_PG = { postgres: { id: 'rsgkD1YxrO2lpYtT', name: 'Postgres – Consult (consult_app)' } };

export function codeNodeSource() {
  const render = read('src/render.js').toString()
    .replace(/\/\/ @export-start[\s\S]*?\/\/ @export-end\n?/, '');
  const glue = read('src/code-node.js').toString()
    .replace('__HEADER_PNG_BASE64__', read('assets/header.png').toString('base64'))
    .replace('__FOOTER_PNG_BASE64__', read('assets/footer.png').toString('base64'));
  return render + '\n' + glue;
}

const LOAD_SQL = `SELECT c.id                                  AS consult_id,
       o.output_type,
       $3::text                              AS format,
       COALESCE(o.final_text, o.draft_text)  AS letter_text,
       to_char(c.approved_at AT TIME ZONE 'America/New_York', 'FMMonth FMDD, YYYY') AS letter_date,
       p.first_name,
       p.last_name,
       c.composite_image
FROM consult.consults c
JOIN consult.patients p ON p.id = c.patient_id
JOIN consult.outputs  o ON o.consult_id = c.id
                       AND o.output_type = $2::text || '_letter'
WHERE c.download_token = $1::text
  AND c.status IN ('approved', 'filed')
  AND $2::text IN ('doctor', 'family')
  AND $3::text IN ('pdf', 'docx')
LIMIT 1;`;

const LOG_SQL = `INSERT INTO consult.audit_log (consult_id, action, actor)
VALUES ($1::text, $2::text, $3::text);`;

const NOT_AVAILABLE_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Download not available</title>
<style>
  body { margin: 0; font-family: -apple-system, 'Segoe UI', Roboto, sans-serif; background: #F7F3EE; color: #1F1D1B;
         display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: 24px; box-sizing: border-box; }
  .card { background: #fff; border: 1px solid #EBE3D9; border-radius: 16px; max-width: 440px; width: 100%;
          padding: 40px 32px; text-align: center; box-shadow: 0 8px 30px rgba(31,29,27,0.08); }
  h1 { font-size: 20px; font-weight: 600; margin: 0 0 12px; }
  p { font-size: 15px; color: #7A716A; line-height: 1.5; margin: 0; }
</style>
</head>
<body>
  <div class="card">
    <h1>This download isn't available</h1>
    <p>Letters can be downloaded once they're approved. If they were reopened for edits, approve them again, then download from the review screen.</p>
  </div>
</body>
</html>`;

export function buildWorkflow() {
  return {
    name: 'C02 Consult - Download Letter',
    nodes: [
      {
        parameters: {
          path: 'consult/letter/:token/:doc/:format',
          responseMode: 'responseNode',
          options: {},
        },
        type: 'n8n-nodes-base.webhook',
        typeVersion: 2.1,
        position: [-1040, -96],
        id: '3a1f6c2e-8b4d-4f0a-9c7e-1d2b3c4d5e01',
        name: 'Download requested',
        webhookId: WEBHOOK_ID,
      },
      {
        parameters: {
          operation: 'executeQuery',
          query: LOAD_SQL,
          options: {
            queryReplacement: '={{ [$json.params.token, $json.params.doc, $json.params.format] }}',
          },
        },
        type: 'n8n-nodes-base.postgres',
        typeVersion: 2.6,
        position: [-816, -96],
        id: '3a1f6c2e-8b4d-4f0a-9c7e-1d2b3c4d5e02',
        name: 'Load approved letter',
        alwaysOutputData: true,
        credentials: CONSULT_PG,
      },
      {
        parameters: {
          conditions: {
            options: { caseSensitive: true, leftValue: '', typeValidation: 'loose', version: 3 },
            conditions: [
              {
                id: '3a1f6c2e-8b4d-4f0a-9c7e-1d2b3c4d5e10',
                leftValue: '={{ !!$json.consult_id }}',
                rightValue: '',
                operator: { type: 'boolean', operation: 'true', singleValue: true },
              },
            ],
            combinator: 'and',
          },
          looseTypeValidation: true,
          options: {},
        },
        type: 'n8n-nodes-base.if',
        typeVersion: 2.3,
        position: [-592, -96],
        id: '3a1f6c2e-8b4d-4f0a-9c7e-1d2b3c4d5e03',
        name: 'Letter found?',
      },
      {
        parameters: { jsCode: codeNodeSource() },
        type: 'n8n-nodes-base.code',
        typeVersion: 2,
        position: [-352, -192],
        id: '3a1f6c2e-8b4d-4f0a-9c7e-1d2b3c4d5e04',
        name: 'Build file',
      },
      {
        parameters: {
          respondWith: 'binary',
          options: {
            responseHeaders: {
              entries: [
                { name: 'Content-Type', value: '={{ $json.mime }}' },
                { name: 'Content-Disposition', value: '=attachment; filename="{{ $json.filename }}"' },
                { name: 'Cache-Control', value: 'no-store' },
                { name: 'X-Content-Type-Options', value: 'nosniff' },
              ],
            },
          },
        },
        type: 'n8n-nodes-base.respondToWebhook',
        typeVersion: 1.5,
        position: [-112, -288],
        id: '3a1f6c2e-8b4d-4f0a-9c7e-1d2b3c4d5e05',
        name: 'Send file',
      },
      {
        parameters: {
          operation: 'executeQuery',
          query: LOG_SQL,
          options: {
            queryReplacement: '={{ [$json.consult_id, $json.action, $json.actor] }}',
          },
        },
        type: 'n8n-nodes-base.postgres',
        typeVersion: 2.6,
        position: [-112, -96],
        id: '3a1f6c2e-8b4d-4f0a-9c7e-1d2b3c4d5e06',
        name: 'Log download',
        credentials: CONSULT_PG,
      },
      {
        parameters: {
          respondWith: 'text',
          responseBody: NOT_AVAILABLE_HTML,
          options: {
            responseCode: 404,
            responseHeaders: {
              entries: [
                { name: 'Content-Type', value: 'text/html; charset=utf-8' },
                { name: 'Cache-Control', value: 'no-store' },
              ],
            },
          },
        },
        type: 'n8n-nodes-base.respondToWebhook',
        typeVersion: 1.5,
        position: [-352, 64],
        id: '3a1f6c2e-8b4d-4f0a-9c7e-1d2b3c4d5e07',
        name: 'Not available',
      },
    ],
    pinData: {},
    connections: {
      'Download requested': { main: [[{ node: 'Load approved letter', type: 'main', index: 0 }]] },
      'Load approved letter': { main: [[{ node: 'Letter found?', type: 'main', index: 0 }]] },
      'Letter found?': {
        main: [
          [{ node: 'Build file', type: 'main', index: 0 }],
          [{ node: 'Not available', type: 'main', index: 0 }],
        ],
      },
      'Build file': {
        main: [[
          { node: 'Send file', type: 'main', index: 0 },
          { node: 'Log download', type: 'main', index: 0 },
        ]],
      },
    },
    active: false,
    settings: { executionOrder: 'v1', binaryMode: 'separate' },
    tags: [],
  };
}

// The deployed workflow (live/C02_export.json, exported from n8n) is the template:
// only the Build file code is replaced, so every other node setting stays as deployed.
export function buildFromLive() {
  const live = JSON.parse(read('live/C02_export.json').toString());
  const node = live.nodes.find(n => n.name === 'Build file');
  node.parameters.jsCode = codeNodeSource();
  return live;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const out = path.join(root, 'C02_Consult_-_Download_Letter.json');
  writeFileSync(out, JSON.stringify(buildFromLive(), null, 2) + '\n');
  console.log('wrote', out);
  // The same code as a plain file, for pasting straight into the Build file node.
  const code = path.join(root, 'C02_Build_file_code.js');
  writeFileSync(code, codeNodeSource());
  console.log('wrote', code);
}
