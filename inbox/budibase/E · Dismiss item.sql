-- Budibase query "E · Dismiss item" (Inbox DB, Function: Update).
-- Parameters (Default: blank): id, email
-- Sets aside a message that needs no chart note (or a held one from an unknown sender).
UPDATE inbox.items i
   SET status     = 'dismissed',
       filed_by   = lower({{ email }}::text),
       filed_at   = now(),
       updated_at = now()
 WHERE i.id = CASE WHEN trim({{ id }}::text) ~ '^[0-9]+$' THEN trim({{ id }}::text)::bigint END
   AND i.status IN ('new', 'held', 'error')
   AND i.practice_id IN (SELECT pu.practice_id FROM public.practice_users pu
                          WHERE lower(pu.email) = lower({{ email }}::text) AND pu.active)
RETURNING i.id;
