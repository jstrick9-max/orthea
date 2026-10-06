-- Budibase query "C · Approve consult" (Consult DB). Replace the whole SQL.
-- Change: approving also issues a fresh download_token.
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
     SET status = 'approved',
         approved_by = lower({{ email }}),
         approved_at = now(),
         download_token = replace(gen_random_uuid()::text, '-', '') ||
                          replace(gen_random_uuid()::text, '-', ''),
         updated_at = now()
    FROM target t
   WHERE c.id = t.id
     AND c.status = 'review'
     AND NOT c.notes_edited
     AND (jsonb_array_length(COALESCE(c.conflicts, '[]'::jsonb)) = 0 OR c.flags_reviewed)
     AND EXISTS (SELECT 1 FROM consult.outputs o
                  WHERE o.consult_id = c.id AND o.output_type = 'doctor_letter')
     AND EXISTS (SELECT 1 FROM consult.outputs o
                  WHERE o.consult_id = c.id AND o.output_type = 'family_letter')
  RETURNING c.id
), logged AS (
  INSERT INTO consult.audit_log (consult_id, action, actor)
  SELECT id::text, 'approved', lower({{ email }}) FROM upd
)
SELECT id FROM upd;
