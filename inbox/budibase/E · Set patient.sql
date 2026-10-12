-- Budibase query "E · Set patient" (Inbox DB, Function: Update).
-- Parameters (Default: blank): id, email, firstName, lastName, dob
-- Saves the patient name and date of birth (MM/DD/YYYY) as confirmed by staff, on a message
-- still to be filed. A blank date of birth clears it. Returns the message id.
UPDATE inbox.items i
   SET patient_first = NULLIF(regexp_replace(trim({{ firstName }}::text), '\s+', ' ', 'g'), ''),
       patient_last  = NULLIF(regexp_replace(trim({{ lastName }}::text), '\s+', ' ', 'g'), ''),
       patient_dob   = CASE WHEN trim({{ dob }}::text) ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$'
                              THEN to_date(trim({{ dob }}::text), 'MM/DD/YYYY')
                            WHEN trim({{ dob }}::text) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
                              THEN substr(trim({{ dob }}::text), 1, 10)::date
                       END,
       updated_at    = now()
 WHERE i.id = CASE WHEN trim({{ id }}::text) ~ '^[0-9]+$' THEN trim({{ id }}::text)::bigint END
   AND i.status IN ('new', 'error')
   AND i.practice_id IN (SELECT pu.practice_id FROM public.practice_users pu
                          WHERE lower(pu.email) = lower({{ email }}::text) AND pu.active)
RETURNING i.id;
