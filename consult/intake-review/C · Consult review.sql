-- Budibase query "C · Consult review" (Consult DB) — replace the whole SQL. Parameters unchanged.
-- Change (2026-10-10): adds two columns —
--   needs_input  = "yes" while the consult is a draft with no transcript and no TMT notes
--   from_dolphin = "yes" when the patient is linked to Dolphin
-- (family_intro_view / family_rest_view split for the composite photo is unchanged.)
SELECT q.*,
       fmt.doctor_v AS doctor_letter_view,
       fmt.family_v AS family_letter_view,
       fs.intro AS family_intro_view,
       fs.rest  AS family_rest_view,
       replace(q.tmt_summary, '~', E'\\~') AS tmt_summary_view,
       replace(q.tmt_notes,   '~', E'\\~') AS tmt_notes_view,
       replace(q.transcript,  '~', E'\\~') AS transcript_view
FROM (
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
       CASE WHEN c.status = 'draft'
             AND NULLIF(btrim(COALESCE(c.tmt_notes, '')), '') IS NULL
             AND NULLIF(btrim(COALESCE(c.transcript, '')), '') IS NULL
            THEN 'yes' ELSE 'no' END AS needs_input,
       CASE WHEN p.dolphin_guid IS NOT NULL THEN 'yes' ELSE 'no' END AS from_dolphin,
       CASE WHEN c.notes_edited THEN 'yes' ELSE 'no' END AS notes_edited,
       (SELECT count(*) FROM jsonb_array_elements(COALESCE(c.conflicts, '[]'::jsonb))) AS conflict_count,
       (SELECT string_agg(
                 CASE WHEN e->>'type' = 'conflict'
                      THEN '**' || (e->>'field') || ':** your notes say "' || (e->>'record_says') ||
                           '", the transcript says "' || (e->>'transcript_says') || '". ' || COALESCE(e->>'question', '')
                      ELSE '**' || (e->>'field') || ':** ' || COALESCE(e->>'question', e->>'record_says')
                 END,
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
LIMIT 1
) q
-- Display formatting for the two letters (the stored text is not changed):
--   * mailing address lines (everything before "Dear …," / "Hi …,") become one block
--   * "•" lines become a Markdown bullet list and numbered lines a numbered list; the
--     blank lines between items are removed so the CSS controls the gap between them
--   * short title lines (section headings) are bolded, as before
CROSS JOIN LATERAL (
  SELECT max(f.v) FILTER (WHERE t.k = 'd') AS doctor_v,
         max(f.v) FILTER (WHERE t.k = 'f') AS family_v
  FROM (VALUES ('d', q.doctor_letter), ('f', q.family_letter)) AS t(k, raw)
  CROSS JOIN LATERAL (
    SELECT COALESCE(substring(t.raw from E'^(.*?)\n\n(?:Dear|Hi|Hello) [^\n]*,\n'), '') AS addr
  ) a
  CROSS JOIN LATERAL (
    SELECT replace(a.addr, E'\n\n', E'\n') ||
           replace(
             regexp_replace(
               regexp_replace(
                 regexp_replace(substr(t.raw, length(a.addr) + 1), E'(^|\n)\u2022 ', E'\\1- ', 'g'),
                 E'^((?:- |[0-9]+\\. )[^\n]*)\n\n(?=- |[0-9]+\\. )', E'\\1\n', 'gn'),
               E'(^|\n)([A-Z][A-Za-z -]{2,40})(\n)', E'\\1**\\2**\\3', 'g'),
             '~', E'\\~') AS v
  ) f
) fmt
-- Family letter split for the composite photo: the intro runs through the first paragraph
-- after "Dear …," / "Hi …,"; the photo (Composite Provider) sits between intro and rest.
-- Splits on blank lines, so the two parts join back to exactly the formatted letter.
CROSS JOIN LATERAL (
  SELECT string_agg(u.e, E'\n\n' ORDER BY u.n) FILTER (WHERE u.n <= g.n + 1) AS intro,
         string_agg(u.e, E'\n\n' ORDER BY u.n) FILTER (WHERE u.n >  g.n + 1) AS rest
  FROM unnest(string_to_array(fmt.family_v, E'\n\n')) WITH ORDINALITY AS u(e, n)
  CROSS JOIN (
    SELECT COALESCE(min(x.n), 0) AS n
      FROM unnest(string_to_array(fmt.family_v, E'\n\n')) WITH ORDINALITY AS x(e, n)
     WHERE x.e ~ '^(Dear|Hi|Hello) [^\n]*,$'
  ) g
) fs;