-- Budibase query "C · Consult review" (Consult DB). Replace the whole SQL.
-- Change: one new column, download_token (only returned once approved).
SELECT c.id,
       c.status,
       CASE WHEN c.status = 'approved' THEN 'locked'
            WHEN c.status <> 'review'  THEN 'wait'
            WHEN c.flags_reviewed      THEN 'on'
            ELSE 'off' END AS check_state,
       CASE WHEN c.status = 'approved' THEN 'done'
            WHEN c.status = 'review'
             AND NOT c.notes_edited
             AND (jsonb_array_length(COALESCE(c.conflicts, '[]'::jsonb)) = 0 OR c.flags_reviewed)
                 THEN 'ready'
            ELSE 'blocked' END AS approve_state,
              c.approved_by,
       to_char(c.approved_at AT TIME ZONE 'America/New_York', 'FMMon DD, YYYY') AS approved_on,
       CASE WHEN c.status IN ('approved', 'filed') THEN c.download_token END AS download_token,
              CASE WHEN c.status = 'review' THEN 'yes' ELSE 'no' END AS can_edit,
       CASE WHEN c.notes_edited THEN 'yes' ELSE 'no' END AS notes_edited,
       (SELECT count(*) FROM jsonb_array_elements(COALESCE(c.conflicts, '[]'::jsonb))) AS conflict_count,
       (SELECT string_agg(
                 e->>'field' || ': your notes say "' || (e->>'record_says') ||
                 '" — the transcript says "' || (e->>'transcript_says') || '"',
                 E'\n\n')
          FROM jsonb_array_elements(COALESCE(c.conflicts, '[]'::jsonb)) e) AS conflict_text,
       c.consult_date,
       initcap(replace(c.consult_type, '_', ' ')) AS consult_type,
              replace(c.tmt_notes, '\n', E'\n') AS tmt_notes,
       replace(c.transcript, '\n', E'\n\n') AS transcript,
       c.created_at,
       d.display_name AS doctor_name,
       p.dolphin_patient_id,
       p.first_name,
       p.last_name,
              (SELECT regexp_replace(
                 regexp_replace(COALESCE(o.final_text, o.draft_text), E'\n+', E'\n\n', 'g'),
                 E'(Thanks,|Best,)\n\n', E'\\1\n', 'g')
          FROM consult.outputs o
         WHERE o.consult_id = c.id AND o.output_type = 'doctor_letter') AS doctor_letter,
       (SELECT regexp_replace(
                 regexp_replace(COALESCE(o.final_text, o.draft_text), E'\n+', E'\n\n', 'g'),
                 E'(Thanks,|Best,)\n\n', E'\\1\n', 'g')
          FROM consult.outputs o
         WHERE o.consult_id = c.id AND o.output_type = 'family_letter') AS family_letter,
       (SELECT COALESCE(o.final_text, o.draft_text) FROM consult.outputs o
         WHERE o.consult_id = c.id AND o.output_type = 'tmt_summary')   AS tmt_summary
FROM consult.consults c
JOIN consult.patients p ON p.id = c.patient_id
LEFT JOIN public.doctors d ON d.id = c.doctor_id
WHERE c.patient_id = CASE WHEN trim({{ patientId }}) ~ '^[0-9]+$'
                          THEN trim({{ patientId }})::bigint END
  AND c.practice_id IN (
        SELECT pu.practice_id FROM public.practice_users pu
        WHERE lower(pu.email) = lower({{ email }}) AND pu.active
      )
ORDER BY c.created_at DESC
LIMIT 1;
