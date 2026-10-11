-- Budibase query "E · Reopen item" (Inbox DB, Function: Update).
-- Parameters (Default: blank): id, email
-- Puts a filed or dismissed message back in the To file list. A held message stays held.
UPDATE inbox.items i
   SET status     = 'new',
       filed_by   = NULL,
       filed_at   = NULL,
       updated_at = now()
 WHERE i.id = CASE WHEN trim({{ id }}::text) ~ '^[0-9]+$' THEN trim({{ id }}::text)::bigint END
   AND (i.status = 'filed' OR (i.status = 'dismissed' AND i.chart_note IS NOT NULL))
   AND i.practice_id IN (SELECT pu.practice_id FROM public.practice_users pu
                          WHERE lower(pu.email) = lower({{ email }}::text) AND pu.active)
RETURNING i.id;
