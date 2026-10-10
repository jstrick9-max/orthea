-- NEW Budibase query "C · Save consult input" (Consult DB, Function: Update).
-- Parameters (Default: leave blank): patientId, email, transcript, tmtNotes
-- Fills in the transcript and/or TMT notes on the patient's latest consult while it is still a
-- draft (saved without input). Blank fields are left as they are. Returns the consult id, or no
-- row if nothing was saved.
WITH target AS (
  SELECT c.id FROM consult.consults c
   WHERE c.patient_id = CASE WHEN trim({{ patientId }}::text) ~ '^[0-9]+$'
                             THEN trim({{ patientId }}::text)::bigint END
     AND c.practice_id IN (
           SELECT pu.practice_id FROM public.practice_users pu
            WHERE lower(pu.email) = lower({{ email }}::text) AND pu.active
         )
   ORDER BY c.created_at DESC
   LIMIT 1
), inp AS (
  SELECT NULLIF(NULLIF(trim(replace({{ transcript }}::text, '\n', E'\n')), ''), '``') AS transcript,
         NULLIF(NULLIF(trim(replace({{ tmtNotes }}::text,   '\n', E'\n')), ''), '``') AS tmt_notes
), upd AS (
  UPDATE consult.consults c
     SET transcript = COALESCE(inp.transcript, c.transcript),
         tmt_notes  = COALESCE(inp.tmt_notes,  c.tmt_notes),
         updated_at = now()
    FROM target t, inp
   WHERE c.id = t.id
     AND c.status = 'draft'
     AND (inp.transcript IS NOT NULL OR inp.tmt_notes IS NOT NULL)
  RETURNING c.id
), logged AS (
  INSERT INTO consult.audit_log (consult_id, action, actor)
  SELECT id::text, 'added consult input', lower({{ email }}::text) FROM upd
)
SELECT id FROM upd;
