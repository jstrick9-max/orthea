-- NEW Budibase query "C · Save letter details" (Consult DB, Function: Update)
-- Parameters (all default blank): patientId, email, parent1First, parent1Last, parent2First,
--   parent2Last, mailingAddress, refId, origRefId, refAddress, feeTotal, feeInitial, feeMonthly, feeMonths
-- Names/addresses: blank = keep what’s on file. Addresses keep their line breaks (Budibase
--   sends them as a literal \n, turned back into real newlines here).  Fees: blank = clear (letter drops Fees).
-- Referrer: refId re-links the patient. refAddress belongs to the dentist the form loaded with
--   (origRefId), so it is saved only when the dentist was not changed, or when the patient had
--   no dentist before (then it goes to the newly picked one).
-- Only saves while the latest consult is in "review".
WITH me AS (
  SELECT pu.practice_id FROM public.practice_users pu
  WHERE lower(pu.email) = lower({{ email }}) AND pu.active
),
target AS (
  SELECT c.id, c.patient_id, c.practice_id
    FROM consult.consults c
   WHERE c.patient_id = CASE WHEN trim({{ patientId }}) ~ '^[0-9]+$'
                             THEN trim({{ patientId }})::bigint END
     AND c.practice_id IN (SELECT practice_id FROM me)
   ORDER BY c.created_at DESC
   LIMIT 1
),
ok AS (
  SELECT t.* FROM target t
  JOIN consult.consults c ON c.id = t.id
  WHERE c.status = 'review'
),
inp AS (
  SELECT NULLIF(NULLIF(trim({{ parent1First }}), ''), '``')   AS p1_first,
         NULLIF(NULLIF(trim({{ parent1Last }}), ''), '``')    AS p1_last,
         NULLIF(NULLIF(trim({{ parent2First }}), ''), '``')   AS p2_first,
         NULLIF(NULLIF(trim({{ parent2Last }}), ''), '``')    AS p2_last,
         NULLIF(NULLIF(trim(regexp_replace(replace({{ mailingAddress }}, '\n', E'\n'), '[ \t]*\n[ \t]*', E'\n', 'g')), ''), '``') AS mailing_address,
         CASE WHEN trim({{ refId }})     ~ '^[0-9]+$' THEN trim({{ refId }})::bigint     END AS ref_id,
         CASE WHEN trim({{ origRefId }}) ~ '^[0-9]+$' THEN trim({{ origRefId }})::bigint END AS orig_ref_id,
         NULLIF(NULLIF(trim(regexp_replace(replace({{ refAddress }}, '\n', E'\n'), '[ \t]*\n[ \t]*', E'\n', 'g')), ''), '``') AS ref_address,
         NULLIF(regexp_replace(COALESCE({{ feeTotal }}, ''),   '[^0-9.]', '', 'g'), '')::numeric        AS fee_total,
         NULLIF(regexp_replace(COALESCE({{ feeInitial }}, ''), '[^0-9.]', '', 'g'), '')::numeric        AS fee_initial,
         NULLIF(regexp_replace(COALESCE({{ feeMonthly }}, ''), '[^0-9.]', '', 'g'), '')::numeric        AS fee_monthly,
         round(NULLIF(regexp_replace(COALESCE({{ feeMonths }}, ''), '[^0-9.]', '', 'g'), '')::numeric) AS fee_months
),
newref AS (
  -- the picked dentist, only if it belongs to this practice
  SELECT r.id FROM consult.referring_doctors r, ok, inp
   WHERE r.id = inp.ref_id AND r.practice_id = ok.practice_id
),
pat AS (
  UPDATE consult.patients p
     SET parent1_first_name  = COALESCE(inp.p1_first, p.parent1_first_name),
         parent1_last_name   = COALESCE(inp.p1_last,  p.parent1_last_name),
         parent2_first_name  = COALESCE(inp.p2_first, p.parent2_first_name),
         parent2_last_name   = COALESCE(inp.p2_last,  p.parent2_last_name),
         mailing_address     = COALESCE(inp.mailing_address, p.mailing_address),
         referring_doctor_id = COALESCE((SELECT id FROM newref), p.referring_doctor_id)
    FROM ok, inp
   WHERE p.id = ok.patient_id
  RETURNING p.id
),
refaddr AS (
  UPDATE consult.referring_doctors r
     SET mailing_address = inp.ref_address
    FROM ok, inp
   WHERE inp.ref_address IS NOT NULL
     AND r.practice_id = ok.practice_id
     AND r.id = CASE
                  WHEN inp.orig_ref_id IS NULL THEN (SELECT id FROM newref)   -- first dentist for this patient
                  WHEN inp.ref_id IS NULL OR inp.ref_id = inp.orig_ref_id THEN inp.orig_ref_id
                END                                                           -- re-linked: address belongs to the old one, skip
  RETURNING r.id
),
fees AS (
  UPDATE consult.consults c
     SET fee_total   = inp.fee_total,
         fee_initial = inp.fee_initial,
         fee_monthly = inp.fee_monthly,
         fee_months  = inp.fee_months,
         updated_at  = now()
    FROM ok, inp
   WHERE c.id = ok.id
  RETURNING c.id
),
logged AS (
  INSERT INTO consult.audit_log (consult_id, action, actor)
  SELECT id::text, 'edited letter details', lower({{ email }}) FROM fees
)
SELECT id FROM fees;
