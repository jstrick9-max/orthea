SELECT p.id,
       p.dolphin_patient_id,
       p.first_name,
       p.last_name,
       p.dob,
       p.parent1_first_name,
       p.parent2_first_name,
       r.full_name     AS referring_dentist,
       c.id            AS latest_consult_id,
       c.status        AS latest_consult_status,
       c.consult_date  AS latest_consult_date,
       CASE WHEN c.id IS NOT NULL THEN '/review' ELSE '/intake' END AS destination,
       c.flag_count    AS conflict_count,
       CASE
         WHEN c.id IS NULL THEN 'No consult'
         WHEN c.status = 'review' AND c.flag_count = 1 THEN '1 flag'
         WHEN c.status = 'review' AND c.flag_count > 1 THEN c.flag_count::text || ' flags'
         ELSE initcap(c.status)
       END AS status_label
FROM consult.patients p
LEFT JOIN consult.referring_doctors r ON r.id = p.referring_doctor_id
LEFT JOIN LATERAL (
  SELECT id, status, consult_date,
         (SELECT count(*) FROM jsonb_array_elements(COALESCE(conflicts, '[]'::jsonb))) AS flag_count
  FROM consult.consults
  WHERE patient_id = p.id
  ORDER BY created_at DESC
  LIMIT 1
) c ON true
WHERE p.archived_at IS NULL
  AND p.practice_id IN (
        SELECT pu.practice_id
        FROM public.practice_users pu
        WHERE lower(pu.email) = lower({{ email }})
          AND pu.active
      )
  AND EXISTS (
        SELECT 1 FROM consult.practice_settings ps
        WHERE ps.practice_id = p.practice_id
          AND ps.consult_enabled
      )
ORDER BY p.dolphin_patient_id;
