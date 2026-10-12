-- Orthea Inbox — on its own island: no Consult patients, no matching.
-- The patient is kept as the message names them (Claude reads first name, last name and
-- birthday); staff confirm or correct those three fields before filing.
-- Run after 01–03. Beekeeper, admin connection, Auto Commit. Safe to re-run.
-- Check the editor ends with the line  -- END OF 04_island.sql  before Run All.

-- The patient as confirmed by staff (starts as what the message says)
ALTER TABLE inbox.items ADD COLUMN IF NOT EXISTS patient_first text;
ALTER TABLE inbox.items ADD COLUMN IF NOT EXISTS patient_last  text;
ALTER TABLE inbox.items ADD COLUMN IF NOT EXISTS patient_dob   date;

UPDATE inbox.items
   SET patient_first = COALESCE(patient_first, said_first),
       patient_last  = COALESCE(patient_last,  said_last),
       patient_dob   = COALESCE(patient_dob,   said_dob);

-- No more links to Consult patients
UPDATE inbox.items SET patient_id = NULL, match = NULL WHERE patient_id IS NOT NULL OR match IS NOT NULL;

-- complete(): store what Claude read; no lookup anywhere else
DROP FUNCTION IF EXISTS inbox.complete(bigint, text, text, text, text, text, text, text);
CREATE FUNCTION inbox.complete(
  p_item_id    bigint,
  p_transcript text,
  p_summary    text,
  p_chart_note text,
  p_first      text,
  p_last       text,
  p_dob        text,     -- YYYY-MM-DD or MM/DD/YYYY; anything else is ignored
  p_error      text
)
RETURNS TABLE (item_id bigint, status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, inbox
AS $$
DECLARE
  v_status text;
  v_first  text := NULLIF(regexp_replace(btrim(COALESCE(p_first, '')), '\s+', ' ', 'g'), '');
  v_last   text := NULLIF(regexp_replace(btrim(COALESCE(p_last, '')), '\s+', ' ', 'g'), '');
  v_dob    date;
BEGIN
  SELECT i.status INTO v_status FROM inbox.items i WHERE i.id = p_item_id;
  IF v_status IS DISTINCT FROM 'processing' THEN
    RETURN;                                     -- unknown, held, or already done
  END IF;

  IF NULLIF(btrim(COALESCE(p_error, '')), '') IS NOT NULL THEN
    UPDATE inbox.items i SET status = 'error', error = left(btrim(p_error), 2000), updated_at = now()
     WHERE i.id = p_item_id;
    RETURN QUERY SELECT p_item_id, 'error'::text;
    RETURN;
  END IF;

  BEGIN
    IF btrim(COALESCE(p_dob, '')) ~ '^\d{4}-\d{2}-\d{2}$' THEN
      v_dob := btrim(p_dob)::date;
    ELSIF btrim(COALESCE(p_dob, '')) ~ '^\d{1,2}/\d{1,2}/\d{4}$' THEN
      v_dob := to_date(btrim(p_dob), 'MM/DD/YYYY');
    END IF;
  EXCEPTION WHEN others THEN v_dob := NULL;
  END;
  IF v_dob < DATE '1901-01-01' OR v_dob > current_date THEN v_dob := NULL; END IF;

  UPDATE inbox.items i
     SET status        = 'new',
         transcript    = NULLIF(btrim(COALESCE(p_transcript, '')), ''),
         summary       = NULLIF(btrim(COALESCE(p_summary, '')), ''),
         chart_note    = NULLIF(btrim(COALESCE(p_chart_note, '')), ''),
         said_first    = v_first,
         said_last     = v_last,
         said_dob      = v_dob,
         patient_first = v_first,
         patient_last  = v_last,
         patient_dob   = v_dob,
         error         = NULL,
         updated_at    = now()
   WHERE i.id = p_item_id;

  RETURN QUERY SELECT p_item_id, 'new'::text;
END;
$$;

REVOKE ALL ON FUNCTION inbox.complete(bigint, text, text, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION inbox.complete(bigint, text, text, text, text, text, text, text) TO inbox_app;

-- Staff can correct the patient fields
GRANT UPDATE (patient_first, patient_last, patient_dob) ON inbox.items TO inbox_app;

-- Inbox no longer sees anything of Consult
REVOKE SELECT ON consult.patients FROM inbox_app;
REVOKE USAGE ON SCHEMA consult FROM inbox_app;

-- Check: expect "false" twice
SELECT has_schema_privilege('inbox_app', 'consult', 'USAGE')            AS can_use_consult,
       has_table_privilege('inbox_app', 'consult.patients', 'SELECT')   AS can_read_consult_patients;
-- END OF 04_island.sql
