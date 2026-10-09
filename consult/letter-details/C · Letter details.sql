-- NEW Budibase query "C · Letter details" (Consult DB, Function: Read)
-- Parameters: patientId (default 1), email (default lso@ortheasecurity.com)
-- Latest consult for the patient, with the family / referrer / fee details its letters use.
-- Fees come back without trailing zeros ("6860", "24") so the form shows clean values.
SELECT c.id                              AS consult_id,
       c.status,
       CASE WHEN c.status = 'review' THEN 'yes' ELSE 'no' END AS can_edit,
       trim_scale(c.fee_total)::text     AS fee_total,
       trim_scale(c.fee_initial)::text   AS fee_initial,
       trim_scale(c.fee_monthly)::text   AS fee_monthly,
       trim_scale(c.fee_months)::text    AS fee_months,
       p.id                              AS patient_id,
       p.parent1_first_name,
       p.parent1_last_name,
       p.parent2_first_name,
       p.parent2_last_name,
       p.mailing_address,
       p.referring_doctor_id::text       AS referring_doctor_id,
       r.full_name                       AS referring_dentist,
       r.mailing_address                 AS referring_address
FROM consult.consults c
JOIN consult.patients p ON p.id = c.patient_id
LEFT JOIN consult.referring_doctors r ON r.id = p.referring_doctor_id
WHERE c.id = (
        SELECT c2.id FROM consult.consults c2
         WHERE c2.patient_id = CASE WHEN trim({{ patientId }}) ~ '^[0-9]+$'
                                    THEN trim({{ patientId }})::bigint END
           AND c2.practice_id IN (
                 SELECT pu.practice_id FROM public.practice_users pu
                  WHERE lower(pu.email) = lower({{ email }}) AND pu.active
               )
         ORDER BY c2.created_at DESC
         LIMIT 1
      );
