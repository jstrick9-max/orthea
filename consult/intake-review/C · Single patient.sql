-- Budibase query "C · Single patient" (Consult DB) — replace the whole SQL. Parameters unchanged
-- (rowId, email). After saving, click Run once so Budibase picks up the new columns.
-- Changes (2026-10-10):
--   * parent_name_missing is true only when NO parent first name is on file (Parent 2 is optional)
--   * from_dolphin = 'yes' when the patient came from / is linked to Dolphin
SELECT p.id,
       p.dolphin_patient_id,
       p.first_name,
       p.last_name,
       p.dob,
       p.parent1_first_name,
       p.parent2_first_name,
       p.parent1_last_name,
       p.parent2_last_name,
       p.mailing_address,
       p.referring_doctor_id,
       r.full_name        AS referring_dentist,
       r.first_name       AS referring_first_name,
       r.mailing_address  AS referring_address,
       (NULLIF(btrim(COALESCE(p.parent1_first_name, '')), '') IS NULL
        AND NULLIF(btrim(COALESCE(p.parent2_first_name, '')), '') IS NULL) AS parent_name_missing,
       (p.mailing_address IS NULL
        OR (p.referring_doctor_id IS NOT NULL AND r.mailing_address IS NULL)) AS address_missing,
       concat_ws(' and ',
         CASE WHEN p.mailing_address IS NULL THEN 'family' END,
         CASE WHEN p.referring_doctor_id IS NOT NULL AND r.mailing_address IS NULL THEN 'referring dentist' END
       ) AS address_missing_for,
       CASE WHEN p.dolphin_guid IS NOT NULL THEN 'yes' ELSE 'no' END AS from_dolphin
FROM consult.patients p
LEFT JOIN consult.referring_doctors r ON r.id = p.referring_doctor_id
WHERE p.id = CASE WHEN trim({{ rowId }}) ~ '^[0-9]+$'
                  THEN trim({{ rowId }})::bigint
             END
  AND p.practice_id IN (
        SELECT pu.practice_id FROM public.practice_users pu
        WHERE lower(pu.email) = lower({{ email }}) AND pu.active
      );
