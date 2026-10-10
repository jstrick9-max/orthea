-- Budibase query "C · Create consult" (Consult DB) — replace the whole SQL. Parameters unchanged.
-- Change (2026-10-10): refuses to create a consult with neither a transcript nor TMT notes.
-- Add these 4 parameters (Default: leave blank): feeTotal, feeInitial, feeMonthly, feeMonths
-- Fees are optional; "$6,860" or "6860" both work. If any of the four is blank the letter leaves Fees out.
INSERT INTO consult.consults
  (practice_id, patient_id, doctor_id, consult_date, consult_type,
   tmt_notes, transcript, composite_url,
   fee_total, fee_initial, fee_monthly, fee_months,
   status, created_by)
SELECT p.practice_id,
       p.id,
       {{ doctorId }}::uuid,
       COALESCE(NULLIF(NULLIF(trim({{ consultDate }}), ''), '``')::date, current_date),
       NULLIF(NULLIF({{ consultType }}, ''), '``'),
       NULLIF(NULLIF(trim({{ tmtNotes }}), ''), '``'),
       NULLIF(NULLIF(trim({{ transcript }}), ''), '``'),
       NULLIF(NULLIF(trim({{ compositeUrl }}), ''), '``'),
       NULLIF(regexp_replace(COALESCE({{ feeTotal }}, ''),   '[^0-9.]', '', 'g'), '')::numeric,
       NULLIF(regexp_replace(COALESCE({{ feeInitial }}, ''), '[^0-9.]', '', 'g'), '')::numeric,
       NULLIF(regexp_replace(COALESCE({{ feeMonthly }}, ''), '[^0-9.]', '', 'g'), '')::numeric,
       NULLIF(regexp_replace(COALESCE({{ feeMonths }}, ''),  '[^0-9]',  '', 'g'), '')::numeric,
       'draft',
       lower({{ email }})
FROM consult.patients p
WHERE p.id = {{ patientId }}::bigint
  AND p.practice_id IN (
        SELECT pu.practice_id FROM public.practice_users pu
        WHERE lower(pu.email) = lower({{ email }}) AND pu.active
      )
  AND EXISTS (
        SELECT 1 FROM public.doctors d
         WHERE d.id = {{ doctorId }}::uuid
          AND d.practice_id = p.practice_id
          AND d.active
          AND d.role = 'Doctor'
      )
  AND (NULLIF(NULLIF(trim({{ tmtNotes }}), ''), '``') IS NOT NULL
       OR NULLIF(NULLIF(trim({{ transcript }}), ''), '``') IS NOT NULL)
RETURNING id;