-- Budibase query "E · File item" (Inbox DB, Function: Update).
-- Parameters (Default: blank): id, email, chartNote
-- Marks a message as filed in the chart (keeping the note as shown on screen) and records who
-- filed it and when. Only a message with a patient can be filed.
UPDATE inbox.items i
   SET status     = 'filed',
       chart_note = COALESCE(NULLIF(trim(replace({{ chartNote }}::text, '\n', E'\n')), ''), i.chart_note),
       filed_by   = lower({{ email }}::text),
       filed_at   = now(),
       updated_at = now()
 WHERE i.id = CASE WHEN trim({{ id }}::text) ~ '^[0-9]+$' THEN trim({{ id }}::text)::bigint END
   AND i.status = 'new'
   AND i.patient_id IS NOT NULL
   AND i.practice_id IN (SELECT pu.practice_id FROM public.practice_users pu
                          WHERE lower(pu.email) = lower({{ email }}::text) AND pu.active)
RETURNING i.id;
