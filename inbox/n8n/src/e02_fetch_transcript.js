// E02 · Sign transcript download — the job is done; fetch its JSON from the bucket.
const p = $('Sign transcription').first().json;
const status = $input.first().json.TranscriptionJob || {};
if (status.TranscriptionJobStatus === 'FAILED') throw new Error('Transcription failed: ' + (status.FailureReason || 'no reason given'));
const key = `transcripts/${p.job}.json`;
const s = awsSign({
  method: 'GET', host: `${BUCKET}.s3.${AWS_REGION}.amazonaws.com`, path: s3Path(key), service: 's3',
  payloadHash: 'UNSIGNED-PAYLOAD', headers: { 'x-amz-content-sha256': 'UNSIGNED-PAYLOAD' }
});
return [{ json: { url: s.url, h: s.headers } }];
