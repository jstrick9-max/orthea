// E02 · Sign transcription — start an Amazon Transcribe job for the voice note.
// The transcript is written back into the same private bucket (transcripts/…).
const p = $input.first().json;
const job = `orthea-inbox-${p.itemId}-${Date.now()}`;
const body = JSON.stringify({
  TranscriptionJobName: job,
  LanguageCode: 'en-US',
  MediaFormat: p.mediaFormat,
  Media: { MediaFileUri: `s3://${BUCKET}/${p.audioKey}` },
  OutputBucketName: BUCKET,
  OutputKey: `transcripts/${job}.json`
});
const s = awsSign({
  method: 'POST', host: `transcribe.${AWS_REGION}.amazonaws.com`, path: '/', service: 'transcribe',
  payloadHash: sha256hex(body),
  headers: { 'x-amz-target': 'Transcribe.StartTranscriptionJob' }
});
return [{ json: { ...p, job, url: s.url, h: s.headers, body } }];
