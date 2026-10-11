// ---- AWS Signature V4 (shared by every Inbox Code node that calls AWS) ----
const crypto = require('crypto');
const AWS_REGION = 'us-east-2';
const BUCKET = $env.INBOX_BUCKET || 'orthea-inbox';
const awsEncode = s => encodeURIComponent(s).replace(/[!'()*]/g, c => '%' + c.charCodeAt(0).toString(16).toUpperCase());
const s3Path = key => '/' + String(key).split('/').map(awsEncode).join('/');
function awsSign({ method, host, path, query = '', headers = {}, payloadHash, service, region = AWS_REGION,
                   key = $env.INBOX_AWS_KEY, secret = $env.INBOX_AWS_SECRET, amzDate }) {
  if (!key || !secret) throw new Error('INBOX_AWS_KEY / INBOX_AWS_SECRET are not set on the n8n server');
  const NL = String.fromCharCode(10);
  amzDate = amzDate || new Date().toISOString().replace(/[:-]|\.\d{3}/g, '');
  const dateStamp = amzDate.slice(0, 8);
  const h = { host, 'x-amz-date': amzDate };
  for (const [k, v] of Object.entries(headers)) h[k.toLowerCase()] = String(v).trim();
  const names = Object.keys(h).sort();
  const canonicalHeaders = names.map(n => n + ':' + h[n] + NL).join('');
  const signedHeaders = names.join(';');
  const sha = d => crypto.createHash('sha256').update(d, 'utf8').digest('hex');
  const hmac = (k, d) => crypto.createHmac('sha256', k).update(d, 'utf8').digest();
  const canonicalRequest = [method, path, query, canonicalHeaders, signedHeaders, payloadHash].join(NL);
  const scope = `${dateStamp}/${region}/${service}/aws4_request`;
  const stringToSign = ['AWS4-HMAC-SHA256', amzDate, scope, sha(canonicalRequest)].join(NL);
  const kSigning = hmac(hmac(hmac(hmac('AWS4' + secret, dateStamp), region), service), 'aws4_request');
  const signature = crypto.createHmac('sha256', kSigning).update(stringToSign, 'utf8').digest('hex');
  const out = { ...h };
  delete out.host;
  out.authorization = `AWS4-HMAC-SHA256 Credential=${key}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;
  return { url: `https://${host}${path}${query ? '?' + query : ''}`, headers: out, signature };
}
const sha256hex = d => crypto.createHash('sha256').update(d, 'utf8').digest('hex');
// ---- end AWS Signature V4 ----
