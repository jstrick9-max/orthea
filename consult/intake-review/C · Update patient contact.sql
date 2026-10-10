-- Budibase query "C · Update patient contact" (Consult DB, Update) — replace the whole SQL.
-- Parameters (Default: leave blank): patientId, parent1First, parent2First, parent1Last, parent2Last,
--   mailingAddress, refAddress, email, refId, newRefName, newRefFirst, newRefPractice, newRefEmail
--   (the last five are new — add them).
-- A blank field means "leave as is", so saving Intake never wipes something already on file.
-- refId: a referring dentist’s id from “C · Referring doctors” sets the patient’s dentist;
--        "__new" with newRefName creates that dentist (with refAddress) and sets it.
WITH me AS (
  SELECT pu.practice_id FROM public.practice_users pu
  WHERE lower(pu.email) = lower({{ email }}::text) AND pu.active
),
inp AS (
  SELECT CASE WHEN trim({{ patientId }}::text) ~ '^[0-9]+$' THEN trim({{ patientId }}::text)::bigint END AS pid,
         NULLIF(NULLIF(trim({{ parent1First }}::text), ''), '``')   AS parent1_first,
         NULLIF(NULLIF(trim({{ parent2First }}::text), ''), '``')   AS parent2_first,
         NULLIF(NULLIF(trim({{ parent1Last }}::text), ''), '``')    AS parent1_last,
         NULLIF(NULLIF(trim({{ parent2Last }}::text), ''), '``')    AS parent2_last,
         NULLIF(NULLIF(trim(regexp_replace(replace({{ mailingAddress }}::text, '\n', E'\n'), '[ \t]*\n[ \t]*', E'\n', 'g')), ''), '``') AS mailing_address,
         NULLIF(NULLIF(trim(regexp_replace(replace({{ refAddress }}::text, '\n', E'\n'), '[ \t]*\n[ \t]*', E'\n', 'g')), ''), '``')     AS ref_address,
         NULLIF(NULLIF(trim({{ refId }}::text), ''), '``')          AS ref_choice,
         NULLIF(NULLIF(trim({{ newRefName }}::text), ''), '``')     AS new_ref_name,
         NULLIF(NULLIF(trim({{ newRefFirst }}::text), ''), '``')    AS new_ref_first,
         NULLIF(NULLIF(trim({{ newRefPractice }}::text), ''), '``') AS new_ref_practice,
         NULLIF(NULLIF(trim({{ newRefEmail }}::text), ''), '``')    AS new_ref_email
),
target AS (
  SELECT p.id, p.practice_id
    FROM consult.patients p, inp
   WHERE p.id = inp.pid
     AND p.practice_id IN (SELECT practice_id FROM me)
),
newref AS (
  INSERT INTO consult.referring_doctors (practice_id, full_name, first_name, practice_name, email, mailing_address)
  SELECT t.practice_id, inp.new_ref_name, inp.new_ref_first, inp.new_ref_practice, inp.new_ref_email, inp.ref_address
    FROM target t, inp
   WHERE inp.ref_choice = '__new' AND inp.new_ref_name IS NOT NULL
  RETURNING id
),
chosen AS (
  SELECT COALESCE(
           (SELECT id FROM newref),
           (SELECT r.id FROM consult.referring_doctors r, target t, inp
             WHERE inp.ref_choice ~ '^[0-9]+$'
               AND r.id = inp.ref_choice::bigint
               AND r.practice_id = t.practice_id)) AS id
),
pat AS (
  UPDATE consult.patients p
     SET parent1_first_name  = COALESCE(inp.parent1_first, p.parent1_first_name),
         parent2_first_name  = COALESCE(inp.parent2_first, p.parent2_first_name),
         parent1_last_name   = COALESCE(inp.parent1_last,  p.parent1_last_name),
         parent2_last_name   = COALESCE(inp.parent2_last,  p.parent2_last_name),
         mailing_address     = COALESCE(inp.mailing_address, p.mailing_address),
         referring_doctor_id = COALESCE((SELECT id FROM chosen), p.referring_doctor_id)
    FROM inp, target t
   WHERE p.id = t.id
  RETURNING p.id, p.referring_doctor_id, p.practice_id
),
refaddr AS (
  -- the dentist now on the patient gets the typed address (a new one already has it)
  UPDATE consult.referring_doctors r
     SET mailing_address = inp.ref_address
    FROM pat, inp
   WHERE r.id = pat.referring_doctor_id
     AND r.practice_id = pat.practice_id
     AND inp.ref_address IS NOT NULL
  RETURNING r.id
)
SELECT id FROM pat;
