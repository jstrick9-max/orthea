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
       COALESCE(i.patient_first, '')                                                   AS patient_first,
       COALESCE(i.patient_last, '')                                                    AS patient_last,
       COALESCE(to_char(i.patient_dob, 'MM/DD/YYYY'), '')                              AS patient_dob,
       trim(COALESCE(i.said_first, '') || ' ' || COALESCE(i.said_last, '')
            || COALESCE(', born ' || to_char(i.said_dob, 'MM/DD/YYYY'), ''))          AS message_names,
       i.error,
       i.filed_by,
       to_char(i.filed_at AT TIME ZONE 'America/New_York', 'Mon DD, YYYY FMHH12:MI AM') AS filed_on
FROM inbox.items i
LEFT JOIN inbox.senders s ON s.practice_id = i.practice_id AND s.email = i.from_email
WHERE i.id = CASE WHEN trim({{ id }}::text) ~ '^[0-9]+$' THEN trim({{ id }}::text)::bigint END
  AND i.practice_id IN (SELECT pu.practice_id FROM public.practice_users pu
                         WHERE lower(pu.email) = lower({{ email }}::text) AND pu.active);
