// E02 · Sign status check — ask whether the transcription job has finished.
// Gives up after about 6 minutes (36 checks, 10 s apart).
if ($runIndex >= 36) throw new Error('Transcription did not finish within 6 minutes');
const p = $('Sign transcription').first().json;
const body = JSON.stringify({ TranscriptionJobName: p.job });
const s = awsSign({
  method: 'POST', host: `transcribe.${AWS_REGION}.amazonaws.com`, path: '/', service: 'transcribe',
  payloadHash: sha256hex(body),
  headers: { 'x-amz-target': 'Transcribe.GetTranscriptionJob' }
});
return [{ json: { job: p.job, url: s.url, h: s.headers, body } }];
