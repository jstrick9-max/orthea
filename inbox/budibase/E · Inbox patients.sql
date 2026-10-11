-- Budibase query "E · Inbox patients" (Inbox DB, Function: Read).
-- Parameters (Default: blank): email
-- The practice patients, for the "Patient" picker on a message.
SELECT p.id,
       p.last_name || ', ' || p.first_name
         || COALESCE(' · ' || to_char(p.dob, 'MM/DD/YYYY'), '')
         || COALESCE(' · ' || p.dolphin_patient_id, '')                AS label
FROM consult.patients p
WHERE p.archived_at IS NULL
  AND p.practice_id IN (SELECT pu.practice_id FROM public.practice_users pu
                         WHERE lower(pu.email) = lower({{ email }}::text) AND pu.active)
ORDER BY lower(p.last_name), lower(p.first_name);
