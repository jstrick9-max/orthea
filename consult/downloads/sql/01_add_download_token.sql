-- Orthea Consult — download links for approved letters.
-- Run ONCE as orthea_admin (schema change). Touches only the consult schema.
--
-- Each approved consult gets a random 64-character token. The download buttons put it
-- in the link to n8n workflow C02, which serves the letter only while the consult is
-- approved. Reopening clears the token, so old links stop working; approving again
-- issues a new one.

ALTER TABLE consult.consults
  ADD COLUMN IF NOT EXISTS download_token text;

CREATE UNIQUE INDEX IF NOT EXISTS consults_download_token_key
  ON consult.consults (download_token)
  WHERE download_token IS NOT NULL;

-- Consults approved before this change get a token too.
UPDATE consult.consults
   SET download_token = replace(gen_random_uuid()::text, '-', '') ||
                        replace(gen_random_uuid()::text, '-', '')
 WHERE status IN ('approved', 'filed')
   AND download_token IS NULL;

-- Check: approved consults now have a token.
SELECT id, status, left(download_token, 8) || '…' AS token_start
  FROM consult.consults
 WHERE status IN ('approved', 'filed');
