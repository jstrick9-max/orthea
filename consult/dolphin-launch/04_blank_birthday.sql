-- Orthea Consult — ignore Dolphin's blank birthday (12/30/1899). Run after 03.
-- Beekeeper, admin connection, Auto Commit. Safe to re-run.
-- Check the editor ends with the line  -- END OF 04_blank_birthday.sql  before Run All.

CREATE OR REPLACE FUNCTION consult.dolphin_match(
  p_practice   uuid,
  p_guid       text,
  p_dolphin_id text,
  p_first      text,
  p_last       text,
  p_birthday   text,
  p_actor      text
)
RETURNS TABLE (patient_id bigint, outcome text, reason text)
LANGUAGE plpgsql
SET search_path = pg_catalog, consult, public
AS $$
DECLARE
  v_guid     text := NULLIF(upper(btrim(COALESCE(p_guid, ''), '{} ')), '');
  v_id       text := NULLIF(btrim(COALESCE(p_dolphin_id, '')), '');
  v_first    text := NULLIF(regexp_replace(btrim(COALESCE(p_first, '')), '\s+', ' ', 'g'), '');
  v_last     text := NULLIF(regexp_replace(btrim(COALESCE(p_last, '')), '\s+', ' ', 'g'), '');
  v_dob      date;
  v_patient  bigint;
  v_outcome  text;
  v_ids      bigint[];
BEGIN
  IF v_guid IS NULL AND v_id IS NULL THEN
    RETURN QUERY SELECT NULL::bigint, NULL::text, 'no Dolphin patient GUID or ID'::text;
    RETURN;
  END IF;

  -- Dolphin sends MM/DD/YYYY; anything else is ignored rather than guessed.
  IF btrim(COALESCE(p_birthday, '')) ~ '^\d{1,2}/\d{1,2}/\d{4}$' THEN
    BEGIN
      v_dob := to_date(btrim(p_birthday), 'MM/DD/YYYY');
      IF to_char(v_dob, 'FMMM/FMDD/YYYY') <> regexp_replace(btrim(p_birthday), '(^|/)0', '\1', 'g') THEN
        v_dob := NULL;                       -- e.g. 02/31/2015 rolled over: reject
      END IF;
    EXCEPTION WHEN others THEN v_dob := NULL;
    END;
  END IF;
  -- Dolphin sends 12/30/1899 (its "no date") when the birthday is blank.
  IF v_dob < DATE '1901-01-01' THEN v_dob := NULL; END IF;

  -- 1. GUID
  IF v_guid IS NOT NULL THEN
    SELECT p.id INTO v_patient FROM consult.patients p
     WHERE p.practice_id = p_practice
       AND p.dolphin_guid IS NOT NULL
       AND upper(btrim(p.dolphin_guid, '{} ')) = v_guid;
    IF v_patient IS NOT NULL THEN v_outcome := 'guid'; END IF;
  END IF;

  -- 2. Dolphin Patient ID, only on patients not yet tied to a GUID
  IF v_patient IS NULL AND v_id IS NOT NULL THEN
    SELECT array_agg(p.id) INTO v_ids FROM consult.patients p
     WHERE p.practice_id = p_practice
       AND btrim(p.dolphin_patient_id) = v_id
       AND (p.dolphin_guid IS NULL OR btrim(p.dolphin_guid, '{} ') = '');
    IF cardinality(v_ids) = 1 THEN v_patient := v_ids[1]; v_outcome := 'dolphin_id'; END IF;
  END IF;

  -- 3. Name + birthday, only on patients with no Dolphin link at all (e.g. made by hand)
  IF v_patient IS NULL AND v_first IS NOT NULL AND v_last IS NOT NULL AND v_dob IS NOT NULL THEN
    SELECT array_agg(p.id) INTO v_ids FROM consult.patients p
     WHERE p.practice_id = p_practice
       AND lower(btrim(p.first_name)) = lower(v_first)
       AND lower(btrim(p.last_name))  = lower(v_last)
       AND p.dob = v_dob
       AND (p.dolphin_guid IS NULL OR btrim(p.dolphin_guid, '{} ') = '')
       AND (p.dolphin_patient_id IS NULL OR btrim(p.dolphin_patient_id) = '');
    IF cardinality(v_ids) = 1 THEN v_patient := v_ids[1]; v_outcome := 'name_dob'; END IF;
  END IF;

  IF v_patient IS NOT NULL THEN
    -- Refresh identity from Dolphin; blanks never overwrite. Un-archive: staff asked for this patient.
    UPDATE consult.patients p
       SET dolphin_guid       = COALESCE(CASE WHEN v_guid IS NOT NULL THEN '{' || v_guid || '}' END, p.dolphin_guid),
           dolphin_patient_id = COALESCE(v_id, p.dolphin_patient_id),
           first_name         = COALESCE(v_first, p.first_name),
           last_name          = COALESCE(v_last, p.last_name),
           dob                = COALESCE(v_dob, p.dob),
           archived_at        = NULL
     WHERE p.id = v_patient;
  ELSE
    IF v_first IS NULL OR v_last IS NULL THEN
      RETURN QUERY SELECT NULL::bigint, NULL::text, 'new patient but Dolphin sent no first or last name'::text;
      RETURN;
    END IF;
    BEGIN
      INSERT INTO consult.patients (practice_id, dolphin_guid, dolphin_patient_id, first_name, last_name, dob)
      VALUES (p_practice, CASE WHEN v_guid IS NOT NULL THEN '{' || v_guid || '}' END, v_id, v_first, v_last, v_dob)
      RETURNING id INTO v_patient;
      v_outcome := 'created';
    EXCEPTION WHEN unique_violation THEN
      -- Two clicks at once both tried to create the same Dolphin patient: use the one that won.
      SELECT p.id INTO v_patient FROM consult.patients p
       WHERE p.practice_id = p_practice AND upper(btrim(p.dolphin_guid, '{} ')) = v_guid;
      v_outcome := 'guid';
    END;
  END IF;

  INSERT INTO consult.audit_log (consult_id, action, actor)
  VALUES ('patient:' || v_patient, 'dolphin launch (' || v_outcome || ')', p_actor);

  RETURN QUERY SELECT v_patient, v_outcome, NULL::text;
END;
$$;

REVOKE ALL ON FUNCTION consult.dolphin_match(uuid, text, text, text, text, text, text) FROM PUBLIC;

-- Patients already saved with the placeholder date: clear it.
UPDATE consult.patients SET dob = NULL WHERE dob < DATE '1901-01-01';

-- Expect no rows:
SELECT id, first_name, last_name, dob FROM consult.patients WHERE dob < DATE '1901-01-01';
-- END OF 04_blank_birthday.sql
