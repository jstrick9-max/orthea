-- NEW Budibase query "C · Wait for composite" (Consult DB, Function: Read)
-- Parameters: patientId (default 1), email (default lso@ortheasecurity.com)
-- Waits up to 12 s for the new photo to be fetched. Returns 'ready', 'none' or 'loading'.
SELECT consult.wait_for_composite(t.id, 12) AS composite
FROM (
  SELECT c.id FROM consult.consults c
   WHERE c.patient_id = CASE WHEN trim({{ patientId }}) ~ '^[0-9]+$'
                             THEN trim({{ patientId }})::bigint END
     AND c.practice_id IN (
           SELECT pu.practice_id FROM public.practice_users pu
            WHERE lower(pu.email) = lower({{ email }}) AND pu.active
         )
   ORDER BY c.created_at DESC
   LIMIT 1
) t;
