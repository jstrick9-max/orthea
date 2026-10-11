-- Budibase query "E · Save note" (Inbox DB, Function: Update).
-- Parameters (Default: blank): id, email, chartNote
-- Saves an edited chart note on a message still to be filed. A blank note is not saved.
UPDATE inbox.items i
   SET chart_note = NULLIF(trim(replace({{ chartNote }}::text, '\n', E'\n')), ''),
       updated_at = now()
 WHERE i.id = CASE WHEN trim({{ id }}::text) ~ '^[0-9]+$' THEN trim({{ id }}::text)::bigint END
   AND i.status = 'new'
   AND NULLIF(trim({{ chartNote }}::text), '') IS NOT NULL
   AND i.practice_id IN (SELECT pu.practice_id FROM public.practice_users pu
                          WHERE lower(pu.email) = lower({{ email }}::text) AND pu.active)
RETURNING i.id;
