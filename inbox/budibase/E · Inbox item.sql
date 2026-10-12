-- Budibase query "E · Inbox item" (Inbox DB, Function: Read).
-- Parameters (Default: blank): id, email
-- One message, only if it belongs to the signed-in user practice.
SELECT i.id,
       i.status,
       CASE i.status WHEN 'new' THEN 'To file' WHEN 'processing' THEN 'Working'
                     WHEN 'error' THEN 'Needs a look' ELSE initcap(i.status) END        AS status_label,
       to_char(i.received_at AT TIME ZONE 'America/New_York', 'Mon DD, YYYY FMHH12:MI AM') AS received,
       COALESCE(NULLIF(s.display_name, ''), NULLIF(i.from_name, ''), i.from_email)                                  AS sender,
       i.from_email,
       COALESCE(i.subject, '')                                                         AS subject,
       COALESCE(i.summary, '')                                                         AS summary,
       COALESCE(i.chart_note, '')                                                      AS chart_note,
       COALESCE(i.transcript, '')                                                      AS transcript,
       COALESCE(i.body_text, '')                                                       AS body_text,
       i.attachments,
       COALESCE((SELECT string_agg(a->>'name', ', ' ORDER BY ord)
                   FROM jsonb_array_elements(i.attachments) WITH ORDINALITY AS t(a, ord)), '') AS attachment_names,
       i.patient_id,
       i.match,
       CASE i.match WHEN 'name_dob' THEN 'Matched on name and date of birth'
                    WHEN 'name'     THEN 'Matched on name (no date of birth in the message)'
                    WHEN 'last_dob' THEN 'Matched on last name and date of birth (check the first name)'
                    WHEN 'manual'   THEN 'Chosen by staff'
                    ELSE 'Not matched: pick the patient' END                          AS match_label,
       trim(COALESCE(i.said_first, '') || ' ' || COALESCE(i.said_last, '')
            || COALESCE(', born ' || to_char(i.said_dob, 'MM/DD/YYYY'), ''))          AS message_names,
       CASE WHEN p.id IS NOT NULL THEN p.first_name || ' ' || p.last_name END          AS patient_name,
       to_char(p.dob, 'MM/DD/YYYY')                                                    AS patient_dob,
       p.dolphin_patient_id,
       i.error,
       i.filed_by,
       to_char(i.filed_at AT TIME ZONE 'America/New_York', 'Mon DD, YYYY FMHH12:MI AM') AS filed_on
FROM inbox.items i
LEFT JOIN consult.patients p ON p.id = i.patient_id
LEFT JOIN inbox.senders s ON s.practice_id = i.practice_id AND s.email = i.from_email
WHERE i.id = CASE WHEN trim({{ id }}::text) ~ '^[0-9]+$' THEN trim({{ id }}::text)::bigint END
  AND i.practice_id IN (SELECT pu.practice_id FROM public.practice_users pu
                         WHERE lower(pu.email) = lower({{ email }}::text) AND pu.active);
