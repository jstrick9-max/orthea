// Builds E01_Inbox_-_Receive.json and E02_Inbox_-_Process.json from src/*.js.
// Usage: node inbox/n8n/build.mjs
import fs from 'fs';
import crypto from 'crypto';
const dir = new URL('./', import.meta.url);
const src = f => fs.readFileSync(new URL('src/' + f, dir), 'utf8');
const SIG = src('sigv4.js');
const PG_INBOX = { postgres: { id: '', name: 'Postgres – Inbox (inbox_app)' } };
const uid = s => crypto.createHash('md5').update(s).digest('hex').replace(/^(.{8})(.{4})(.{4})(.{4})(.{12}).*/, '$1-$2-$3-$4-$5');

function code(name, file, pos, { sig = true, extra = {} } = {}) {
  return { parameters: { jsCode: (sig ? SIG + '\n' : '') + src(file) }, type: 'n8n-nodes-base.code', typeVersion: 2,
           position: pos, id: uid(name), name, ...extra };
}
function pg(name, query, replacement, pos, extra = {}) {
  return { parameters: { operation: 'executeQuery', query, options: { queryReplacement: replacement, ...(extra.options || {}) } },
           type: 'n8n-nodes-base.postgres', typeVersion: 2.6, position: pos, id: uid(name), name, credentials: PG_INBOX,
           ...(extra.node || {}) };
}
function http(name, method, headers, pos, body, extra = {}) {
  const p = {
    method, url: '={{ $json.url }}', sendHeaders: true,
    headerParameters: { parameters: headers.map(h => ({ name: h, value: `={{ $json.h['${h}'] }}` })) },
    options: { timeout: 60000, ...(extra.options || {}) }
  };
  Object.assign(p, body || {});
  return { parameters: p, type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2, position: pos, id: uid(name), name, ...(extra.node || {}) };
}
const ifNode = (name, left, op, pos) => ({
  parameters: { conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'loose', version: 2 },
    conditions: [{ id: uid(name + 'c'), leftValue: left, rightValue: '', operator: op }], combinator: 'and' }, options: {} },
  type: 'n8n-nodes-base.if', typeVersion: 2.2, position: pos, id: uid(name), name
});
const TRUE = { type: 'boolean', operation: 'true', singleValue: true };
const link = (pairs) => {
  const c = {};
  for (const [from, to, out = 0] of pairs) {
    c[from] = c[from] || { main: [] };
    while (c[from].main.length <= out) c[from].main.push([]);
    c[from].main[out].push({ node: to, type: 'main', index: 0 });
  }
  return c;
};
const settings = { executionOrder: 'v1', binaryMode: 'separate', saveDataSuccessExecution: 'none', saveDataErrorExecution: 'all' };
const ERR = { onError: 'continueErrorOutput' };

// ---------------------------------------------------------------- E01
const e01 = {
  name: 'E01 Inbox - Receive',
  nodes: [
    { parameters: { mailbox: 'INBOX', postProcessAction: 'read', format: 'resolved', dataPropertyAttachmentsPrefixName: 'attachment_', options: {} },
      type: 'n8n-nodes-base.emailReadImap', typeVersion: 2, position: [0, 0], id: uid('New email'), name: 'New email',
      credentials: { imap: { id: '', name: 'IMAP – LSO Inbox' } } },
    code('Parse email', 'e01_parse_email.js', [220, 0]),
    pg('Receive', 'SELECT r.*, $2::text AS message_id\nFROM inbox.receive($1, $2, $3, $4, $5, $6, $7::jsonb) r;',
       '={{ [$json.to, $json.messageId, $json.fromEmail, $json.fromName, $json.subject, $json.text, JSON.stringify($json.attachments.map(a => ({ kind: a.kind, name: a.name, mime: a.mime, size: a.size, key: a.key })))] }}',
       [440, 0], { options: { queryBatching: 'independently' } }),
    code('Plan uploads', 'e01_split_uploads.js', [660, 0]),
    ifNode('Upload?', '={{ $json.upload }}', TRUE, [880, 0]),
    http('Upload to S3', 'PUT', ['authorization', 'x-amz-date', 'x-amz-content-sha256', 'x-amz-server-side-encryption'], [1100, -100],
         { sendBody: true, contentType: 'binaryData', inputDataFieldName: 'file' }, { node: { onError: 'continueRegularOutput' } }),
    code('One per message', 'e01_one_per_item.js', [1320, 0], { sig: false }),
    pg('Hand to E02', "SELECT pg_notify('inbox_process', $1::text) AS sent;", '={{ [$json.itemId] }}', [1540, 0])
  ],
  connections: link([
    ['New email', 'Parse email'], ['Parse email', 'Receive'], ['Receive', 'Plan uploads'], ['Plan uploads', 'Upload?'],
    ['Upload?', 'Upload to S3', 0], ['Upload?', 'One per message', 1], ['Upload to S3', 'One per message'], ['One per message', 'Hand to E02']
  ]),
  pinData: {}, active: false, settings, tags: []
};

// ---------------------------------------------------------------- E02
const e02 = {
  name: 'E02 Inbox - Process',
  nodes: [
    { parameters: { triggerMode: 'listenTrigger', channelName: 'inbox_process', options: {} },
      type: 'n8n-nodes-base.postgresTrigger', typeVersion: 1, position: [0, 0], id: uid('Process requested'), name: 'Process requested', credentials: PG_INBOX },
    pg('Load item', "SELECT id, from_name, from_email, received_at, subject, body_text, attachments\nFROM inbox.items\nWHERE id = $1::bigint AND status = 'processing';",
       '={{ [$json.payload] }}', [220, 0]),
    code('Pick voice note', 'e02_pick_audio.js', [440, 0], { sig: false }),
    ifNode('Voice note?', '={{ $json.hasAudio }}', TRUE, [660, 0]),
    code('Sign transcription', 'e02_start_transcribe.js', [880, -200]),
    http('Start transcription', 'POST', ['authorization', 'x-amz-date', 'x-amz-target'], [1100, -200],
         { sendBody: true, contentType: 'raw', rawContentType: 'application/x-amz-json-1.1', body: '={{ $json.body }}' }, { node: ERR }),
    { parameters: { resume: 'timeInterval', amount: 10, unit: 'seconds' }, type: 'n8n-nodes-base.wait', typeVersion: 1.1, position: [1320, -200], id: uid('Wait 10 s'), name: 'Wait 10 s', webhookId: uid('wait-hook') },
    code('Sign status check', 'e02_check_transcribe.js', [1540, -200], { extra: ERR }),
    http('Check status', 'POST', ['authorization', 'x-amz-date', 'x-amz-target'], [1760, -200],
         { sendBody: true, contentType: 'raw', rawContentType: 'application/x-amz-json-1.1', body: '={{ $json.body }}' }, { node: ERR }),
    { parameters: { conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'loose', version: 2 }, combinator: 'or',
        conditions: ['COMPLETED', 'FAILED'].map(v => ({ id: uid('fin' + v), leftValue: '={{ $json.TranscriptionJob.TranscriptionJobStatus }}', rightValue: v,
          operator: { type: 'string', operation: 'equals' } })) }, options: {} },
      type: 'n8n-nodes-base.if', typeVersion: 2.2, position: [1980, -200], id: uid('Finished?'), name: 'Finished?' },
    code('Sign transcript download', 'e02_fetch_transcript.js', [2200, -300], { extra: ERR }),
    http('Download transcript', 'GET', ['authorization', 'x-amz-date', 'x-amz-content-sha256'], [2420, -300], null,
         { node: ERR, options: { response: { response: { responseFormat: 'json' } } } }),
    code('Transcript text', 'e02_transcript_text.js', [2640, -300], { sig: false, extra: ERR }),
    code('No voice note', 'e02_no_transcript.js', [880, 200], { sig: false }),
    code('Sign Claude', 'e02_sign_claude.js', [2860, 0]),
    http('Ask Claude', 'POST', ['authorization', 'x-amz-date', 'content-type'], [3080, 0],
         { sendBody: true, specifyBody: 'json', jsonBody: '={{ $json.body }}' }, { node: ERR }),
    code('Read answer', 'e02_read_answer.js', [3300, 0], { sig: false, extra: ERR }),
    pg('Save', 'SELECT * FROM inbox.complete($1::bigint, $2, $3, $4, $5, $6, $7, NULL);',
       '={{ [$json.itemId, $json.transcript, $json.summary, $json.chartNote, $json.first, $json.last, $json.dob] }}', [3520, 0]),
    code('Error text', 'e02_error_text.js', [3300, 300], { sig: false }),
    pg('Record error', 'SELECT * FROM inbox.complete($1::bigint, NULL, NULL, NULL, NULL, NULL, NULL, $2);',
       '={{ [$json.itemId, $json.error] }}', [3520, 300])
  ],
  connections: link([
    ['Process requested', 'Load item'], ['Load item', 'Pick voice note'], ['Pick voice note', 'Voice note?'],
    ['Voice note?', 'Sign transcription', 0], ['Voice note?', 'No voice note', 1],
    ['Sign transcription', 'Start transcription'], ['Start transcription', 'Wait 10 s', 0], ['Start transcription', 'Error text', 1],
    ['Wait 10 s', 'Sign status check'], ['Sign status check', 'Check status', 0], ['Sign status check', 'Error text', 1],
    ['Check status', 'Finished?', 0], ['Check status', 'Error text', 1],
    ['Finished?', 'Sign transcript download', 0], ['Finished?', 'Wait 10 s', 1],
    ['Sign transcript download', 'Download transcript', 0], ['Sign transcript download', 'Error text', 1],
    ['Download transcript', 'Transcript text', 0], ['Download transcript', 'Error text', 1],
    ['Transcript text', 'Sign Claude', 0], ['Transcript text', 'Error text', 1],
    ['No voice note', 'Sign Claude'],
    ['Sign Claude', 'Ask Claude'], ['Ask Claude', 'Read answer', 0], ['Ask Claude', 'Error text', 1],
    ['Read answer', 'Save', 0], ['Read answer', 'Error text', 1],
    ['Error text', 'Record error']
  ]),
  pinData: {}, active: false, settings, tags: []
};

for (const wf of [e01, e02]) {
  const file = new URL(wf.name.replace(/ - /, '_-_').replace(/ /g, '_') + '.json', dir);
  fs.writeFileSync(file, JSON.stringify(wf, null, 2) + '\n');
  console.log('wrote', file.pathname);
}
