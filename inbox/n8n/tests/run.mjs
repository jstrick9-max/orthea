// Runs the E01/E02 Code-node sources the way n8n does (top-level return, $input/$env/$ globals).
import fs from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const SRC = new URL('../src/', import.meta.url);
const read = f => fs.readFileSync(new URL(f, SRC), 'utf8');
const SIG = read('sigv4.js');
let fail = 0;
const check = (name, ok) => { console.log((ok ? 'ok   ' : 'FAIL ') + name); if (!ok) fail = 1; };
const items = arr => ({ all: () => arr, first: () => arr[0] });
async function run(file, { input = [], env = {}, nodes = {}, runIndex = 0, withSig = true } = {}) {
  const code = (withSig ? SIG + '\n' : '') + read(file);
  const fn = new (Object.getPrototypeOf(async function () {}).constructor)('$input', '$env', '$', '$runIndex', 'require', code);
  const $ = name => { if (!nodes[name]) throw new Error('no node ' + name); return items(nodes[name]); };
  return fn(items(input), { INBOX_AWS_KEY: 'AKIAIOSFODNN7EXAMPLE', INBOX_AWS_SECRET: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', ...env }, $, runIndex, require);
}

// 1. Signature: AWS's published S3 example (GET /test.txt, examplebucket, 2013-05-24)
const sigTest = await run('e02_no_transcript.js', {}).then(async () => {
  const fn = new Function('$env', 'require', SIG + `
    return awsSign({ method: 'GET', host: 'examplebucket.s3.amazonaws.com', path: '/test.txt', service: 's3', region: 'us-east-1',
      amzDate: '20130524T000000Z', payloadHash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      headers: { range: 'bytes=0-9', 'x-amz-content-sha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' } });`);
  return fn({ INBOX_AWS_KEY: 'AKIAIOSFODNN7EXAMPLE', INBOX_AWS_SECRET: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY' }, require);
});
check('SigV4 matches AWS documented example', sigTest.signature === 'f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41');
check('S3 key path encoding', new Function('$env', 'require', SIG + 'return s3Path("lso/ab/1-Voice Memo (2).m4a")')({}, require) === '/lso/ab/1-Voice%20Memo%20%282%29.m4a');

// 2. Parse email (n8n "resolved" format)
const bin = (fileName, mimeType) => ({ fileName, mimeType, fileSize: '12 kB', data: 'x' });
const email = {
  json: { from: { value: [{ address: 'JStrick9@Gmail.com', name: 'Justin S' }] },
          to: { value: [{ address: 'lso.inbox@ortheasecurity.com', name: '' }] },
          subject: 'Fwd: Leo Marsh', text: 'See voice note\r\nthanks', messageId: '<abc@mail.gmail.com>' },
  binary: { attachment_0: bin('Voice Memo.m4a', 'audio/x-m4a'), attachment_1: bin('xray.JPG', 'image/jpeg'), attachment_2: bin('plan.pdf', 'application/pdf') }
};
const parsed = await run('e01_parse_email.js', { input: [email] });
const p = parsed[0].json;
check('from lower-cased, to listed', p.fromEmail === 'jstrick9@gmail.com' && p.to === 'lso.inbox@ortheasecurity.com');
check('attachment kinds audio/image/file', p.attachments.map(a => a.kind).join() === 'audio,image,file');
check('S3 keys under the inbox name, safe names', /^lso\.inbox\/[0-9a-f]{16}\/1-Voice_Memo\.m4a$/.test(p.attachments[0].key) || /^lso\.inbox\//.test(p.attachments[0].key));
check('binary carried as file1..n', Object.keys(parsed[0].binary).join() === 'file1,file2,file3');
const simple = await run('e01_parse_email.js', { input: [{ json: { from: '"Dr. L" <drl@lso.com>', to: 'a@b.com, lso.inbox@ortheasecurity.com', subject: 's', textPlain: 'hi' } }] });
check('"simple" format addresses parsed too', simple[0].json.fromEmail === 'drl@lso.com' && simple[0].json.fromName === 'Dr. L' && simple[0].json.attachments.length === 0);

// 3. Plan uploads
const plan = await run('e01_split_uploads.js', {
  input: [{ json: { item_id: '7', status: 'processing', duplicate: false, message_id: '<abc@mail.gmail.com>' } }],
  nodes: { 'Parse email': parsed } });
check('one signed PUT per attachment', plan.length === 3 && plan.every(i => i.json.upload && /^https:\/\/orthea-inbox\.s3\.us-east-2\.amazonaws\.com\//.test(i.json.url) && i.json.h.authorization));
check('upload carries its file', plan[0].binary.file.fileName === 'Voice Memo.m4a');
const held = await run('e01_split_uploads.js', { input: [{ json: { item_id: '8', status: 'held', duplicate: false, message_id: 'x' } }], nodes: { 'Parse email': parsed } });
check('held message: nothing uploaded', held.length === 0);
const dup = await run('e01_split_uploads.js', { input: [{ json: { item_id: '7', status: 'processing', duplicate: true, message_id: '<abc@mail.gmail.com>' } }], nodes: { 'Parse email': parsed } });
check('duplicate message: nothing uploaded again', dup.length === 0);
const noAtt = await run('e01_split_uploads.js', { input: [{ json: { item_id: '9', status: 'processing', duplicate: false, message_id: '' } }], nodes: { 'Parse email': simple } });
check('no attachments: one "nothing to upload" item', noAtt.length === 1 && noAtt[0].json.upload === false);
const bucketEnv = await run('e01_split_uploads.js', { env: { INBOX_BUCKET: 'orthea-inbox-lso' },
  input: [{ json: { item_id: '7', status: 'processing', duplicate: false, message_id: '<abc@mail.gmail.com>' } }], nodes: { 'Parse email': parsed } });
check('bucket name from INBOX_BUCKET', bucketEnv[0].json.url.startsWith('https://orthea-inbox-lso.s3.'));
const one = await run('e01_one_per_item.js', { input: [{ json: {}, pairedItem: { item: 0 } }, { json: {}, pairedItem: { item: 1 } }], nodes: { 'Plan uploads': plan } });
check('one hand-off per message after 3 uploads', one.length === 1 && one[0].json.itemId === '7');

// 4. E02
const loadItem = { id: '7', from_name: 'Justin S', from_email: 'jstrick9@gmail.com', received_at: '2026-10-11T15:00:00Z', subject: 'Fwd: Leo Marsh',
  body_text: 'See voice note', attachments: p.attachments.concat([{ kind: 'audio', name: 'Audio Message.caf', key: 'k.caf' }]) };
const pick = await run('e02_pick_audio.js', { input: [{ json: loadItem }] });
check('m4a voice note picked for Transcribe', pick[0].json.hasAudio && pick[0].json.mediaFormat === 'mp4' && pick[0].json.audioKey.endsWith('.m4a'));
check('.caf voice note noted as not transcribable', pick[0].json.notes.length === 1 && /\.caf/.test(pick[0].json.notes[0]));
const pickStr = await run('e02_pick_audio.js', { input: [{ json: { ...loadItem, attachments: JSON.stringify([{ kind: 'image', name: 'a.jpg' }]) } }] });
check('attachments as JSON text accepted; no audio → hasAudio false', pickStr[0].json.hasAudio === false);
const start = await run('e02_start_transcribe.js', { input: pick });
const sb = JSON.parse(start[0].json.body);
check('Transcribe job: s3 media URI, output to transcripts/', sb.Media.MediaFileUri.startsWith('s3://orthea-inbox/lso.inbox/') && sb.OutputKey === `transcripts/${start[0].json.job}.json` && start[0].json.h['x-amz-target'] === 'Transcribe.StartTranscriptionJob');
const chk = await run('e02_check_transcribe.js', { nodes: { 'Sign transcription': start }, runIndex: 3 });
check('status check signed', JSON.parse(chk[0].json.body).TranscriptionJobName === start[0].json.job);
let gaveUp = false; try { await run('e02_check_transcribe.js', { nodes: { 'Sign transcription': start }, runIndex: 36 }); } catch (e) { gaveUp = /6 minutes/.test(e.message); }
check('gives up after 36 checks', gaveUp);
let failed = false; try { await run('e02_fetch_transcript.js', { input: [{ json: { TranscriptionJob: { TranscriptionJobStatus: 'FAILED', FailureReason: 'bad media' } } }], nodes: { 'Sign transcription': start } }); } catch (e) { failed = /bad media/.test(e.message); }
check('failed job reported with its reason', failed);
const tt = await run('e02_transcript_text.js', { input: [{ json: { results: { transcripts: [{ transcript: 'Leo Marsh born August 27 2013, extraction done.' }] } } }], withSig: false });
check('transcript text extracted', tt[0].json.transcript.startsWith('Leo Marsh'));
const tt2 = await run('e02_transcript_text.js', { input: [{ json: { data: JSON.stringify({ results: { transcripts: [{ transcript: 'x' }] } }) } }], withSig: false });
check('transcript delivered as text (data) also read', tt2[0].json.transcript === 'x');
const claude = await run('e02_sign_claude.js', { input: tt, nodes: { 'Load item': [{ json: loadItem }], 'Pick voice note': pick } });
const cb = JSON.parse(claude[0].json.body);
check('Bedrock body: version, system, one user message with the transcript', cb.anthropic_version === 'bedrock-2023-05-31' && cb.messages.length === 1 && cb.messages[0].content.includes('extraction done') && cb.messages[0].content.includes('<message>'));
check('Bedrock URL', claude[0].json.url === 'https://bedrock-runtime.us-east-2.amazonaws.com/model/us.anthropic.claude-sonnet-4-6/invoke');
const ans = j => ({ json: { stop_reason: 'end_turn', content: [{ type: 'text', text: j }] } });
const read1 = await run('e02_read_answer.js', { withSig: false, nodes: { 'Sign Claude': claude },
  input: [ans('```json\n{"patient_first_name":"Leo","patient_last_name":"Marsh","patient_dob":"2013-08-27","summary":"Extraction done.","chart_note":"Received voice note from Dr. N on 2026-10-11: extraction done."}\n```')] });
check('answer parsed even inside ``` fences', read1[0].json.first === 'Leo' && read1[0].json.dob === '2013-08-27' && read1[0].json.chartNote.startsWith('Received'));
const read2 = await run('e02_read_answer.js', { withSig: false, nodes: { 'Sign Claude': claude },
  input: [ans('{"patient_first_name":"","patient_last_name":"","patient_dob":"August 2013","summary":"s","chart_note":"n"}')] });
check('non-ISO birthday dropped, empty names kept empty', read2[0].json.dob === '' && read2[0].json.first === '');
let bad = false; try { await run('e02_read_answer.js', { withSig: false, nodes: { 'Sign Claude': claude }, input: [ans('Sorry, I cannot')] }); } catch (e) { bad = /did not return JSON/.test(e.message); }
check('non-JSON answer → error (not a blank note)', bad);
let refused = false; try { await run('e02_read_answer.js', { withSig: false, nodes: { 'Sign Claude': claude }, input: [{ json: { stop_reason: 'refusal', content: [] } }] }); } catch (e) { refused = /declined/.test(e.message); }
check('refusal → error', refused);
const err = await run('e02_error_text.js', { withSig: false, input: [{ json: { error: { message: 'Forbidden' } } }], nodes: { 'Load item': [{ json: loadItem }] } });
check('error text recorded against the message', err[0].json.itemId === '7' && err[0].json.error === 'Forbidden');

console.log(fail ? 'SOME FAILED' : 'ALL PASSED');
process.exit(fail);
