-- New Budibase query "C · Wait for letters" (Consult DB, verb: Read).
-- Parameters: patientId, email (same defaults as C · Consult review).
-- Waits up to 12 s for the patient's latest consult to leave 'generating'.
SELECT consult.wait_for_generation(t.id, 12) AS status
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
