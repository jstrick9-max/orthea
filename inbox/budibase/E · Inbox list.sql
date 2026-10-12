-- Budibase query "E · Inbox list" (Inbox DB, Function: Read).
-- Parameters (Default: blank): email, view   (view: new, filed, held or all; blank means new)
-- Messages for the signed-in user practice, newest first. Times shown in New York time.
SELECT i.id,
       to_char(i.received_at AT TIME ZONE 'America/New_York', 'Mon DD, FMHH12:MI AM') AS received,
       COALESCE(NULLIF(s.display_name, ''), NULLIF(i.from_name, ''), i.from_email)                                  AS sender,
       i.from_email,
       i.subject,
       COALESCE(i.summary, i.subject, '(no summary)')                                   AS summary,
       i.status,
       CASE i.status WHEN 'new' THEN 'To file' WHEN 'processing' THEN 'Working'
                     WHEN 'error' THEN 'Needs a look' ELSE initcap(i.status) END        AS status_label,
       COALESCE(NULLIF(trim(COALESCE(i.patient_first, '') || ' ' || COALESCE(i.patient_last, '')), ''),
                'No patient named')                                                    AS patient_label,
       jsonb_array_length(i.attachments)                                               AS attachment_count
FROM inbox.items i
LEFT JOIN inbox.senders s ON s.practice_id = i.practice_id AND s.email = i.from_email
WHERE i.practice_id IN (SELECT pu.practice_id FROM public.practice_users pu
                         WHERE lower(pu.email) = lower({{ email }}::text) AND pu.active)
  AND CASE lower(COALESCE(NULLIF(trim({{ view }}::text), ''), 'new'))
        WHEN 'new'   THEN i.status IN ('new', 'processing', 'error')
        WHEN 'filed' THEN i.status = 'filed'
        WHEN 'held'  THEN i.status IN ('held', 'dismissed')
        ELSE true
      END
ORDER BY i.received_at DESC
LIMIT 200;
