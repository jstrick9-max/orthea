-- Budibase query "C · Reopen consult" (Consult DB). Replace the whole SQL.
-- Change: reopening clears download_token, so existing download links stop working.
WITH target AS (
  SELECT c.id FROM consult.consults c
   WHERE c.patient_id = CASE WHEN trim({{ patientId }}) ~ '^[0-9]+$'
                             THEN trim({{ patientId }})::bigint END
     AND c.practice_id IN (
           SELECT pu.practice_id FROM public.practice_users pu
            WHERE lower(pu.email) = lower({{ email }}) AND pu.active
         )
   ORDER BY c.created_at DESC
   LIMIT 1
), upd AS (
  UPDATE consult.consults c
     SET status = 'review',
         flags_reviewed = false, flags_reviewed_by = NULL, flags_reviewed_at = NULL,
         approved_by = NULL, approved_at = NULL,
         download_token = NULL,
         updated_at = now()
    FROM target t
   WHERE c.id = t.id AND c.status = 'approved'
  RETURNING c.id
), logged AS (
  INSERT INTO consult.audit_log (consult_id, action, actor)
  SELECT id::text, 'reopened', lower({{ email }}) FROM upd
)
SELECT id FROM upd;
