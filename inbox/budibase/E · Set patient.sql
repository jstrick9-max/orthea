-- Budibase query "E · Set patient" (Inbox DB, Function: Update).
-- Parameters (Default: blank): id, email, patientId
-- Staff pick (or correct) the patient of a message still to be filed. The patient must be
-- one of the same practice. Picking the patient already matched changes nothing.
-- Returns the message id, or no row if nothing changed.
UPDATE inbox.items i
   SET patient_id = p.id,
       match      = 'manual',
       updated_at = now()
  FROM consult.patients p
 WHERE i.id = CASE WHEN trim({{ id }}::text) ~ '^[0-9]+$' THEN trim({{ id }}::text)::bigint END
   AND p.id = CASE WHEN trim({{ patientId }}::text) ~ '^[0-9]+$' THEN trim({{ patientId }}::text)::bigint END
   AND p.practice_id = i.practice_id
   AND i.patient_id IS DISTINCT FROM p.id
   AND i.status IN ('new', 'error')
   AND i.practice_id IN (SELECT pu.practice_id FROM public.practice_users pu
                          WHERE lower(pu.email) = lower({{ email }}::text) AND pu.active)
RETURNING i.id;
