-- Budibase query "C · Set generating" (Consult DB) — replace the whole SQL. Parameters unchanged.
-- Change (2026-10-10): only starts generation when the consult has a transcript or TMT notes.
WITH upd AS (
  UPDATE consult.consults
     SET status = 'generating',
         flags_reviewed = false, flags_reviewed_by = NULL, flags_reviewed_at = NULL,
         notes_edited = false,
         updated_at = now()
   WHERE status NOT IN ('approved', 'filed')
     AND (NULLIF(btrim(COALESCE(tmt_notes, '')), '') IS NOT NULL
          OR NULLIF(btrim(COALESCE(transcript, '')), '') IS NOT NULL)
     AND id = (
       SELECT c.id FROM consult.consults c
        WHERE c.patient_id = CASE WHEN trim({{ patientId }}) ~ '^[0-9]+$'
                                  THEN trim({{ patientId }})::bigint END
          AND c.practice_id IN (
                SELECT pu.practice_id FROM public.practice_users pu
                WHERE lower(pu.email) = lower({{ email }}) AND pu.active
              )
        ORDER BY c.created_at DESC
        LIMIT 1
     )
  RETURNING id
), cleared AS (
  UPDATE consult.outputs o
     SET final_text = NULL
    FROM upd
   WHERE o.consult_id = upd.id
)
SELECT id FROM upd;