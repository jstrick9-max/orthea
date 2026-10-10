-- Orthea Consult — Dolphin toolbar, "nothing installed" version (run after 01 and 02).
-- Run ONCE in Beekeeper on the admin connection, Auto Commit. Safe to re-run.
-- Check the editor ends with the line  -- END OF 03_dolphin_open.sql  before Run All.
--
-- Adds
--   consult.dolphin_match(...)  the patient matching rules, shared by both ways in (internal only)
--   consult.dolphin_open(email, guid, id, first, last, birthday)
--       Budibase /dolphin calls this. The practice comes from the signed-in user, so no key.
-- Changes
--   consult.dolphin_launch(...) now uses dolphin_match (same behaviour; kept for the future
--   launcher / .exe).

-- ---------------------------------------------------------------- shared matching

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

-- ---------------------------------------------------------------- launcher path (key), unchanged behaviour

CREATE OR REPLACE FUNCTION consult.dolphin_launch(
  p_key        text,
  p_guid       text,
  p_dolphin_id text,
  p_first      text,
  p_last       text,
  p_birthday   text
)
RETURNS TABLE (code text, outcome text, reason text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, consult, public
AS $$
DECLARE
  v_practice uuid;
  m          record;
  v_code     text;
BEGIN
  SELECT k.practice_id INTO v_practice
    FROM consult.launch_keys k
    JOIN consult.practice_settings ps ON ps.practice_id = k.practice_id
   WHERE k.key_hash = consult.launch_hash(COALESCE(p_key, ''))
     AND k.revoked_at IS NULL
     AND ps.consult_enabled
     AND ps.dolphin_linked;
  IF v_practice IS NULL THEN
    RETURN QUERY SELECT NULL::text, NULL::text, 'key not recognised, or Dolphin launch is off for this practice'::text;
    RETURN;
  END IF;

  SELECT * INTO m FROM consult.dolphin_match(v_practice, p_guid, p_dolphin_id, p_first, p_last, p_birthday, 'dolphin');
  IF m.patient_id IS NULL THEN
    RETURN QUERY SELECT NULL::text, NULL::text, m.reason;
    RETURN;
  END IF;

  v_code := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  INSERT INTO consult.launch_codes (code_hash, practice_id, patient_id, outcome, expires_at)
  VALUES (consult.launch_hash(v_code), v_practice, m.patient_id, m.outcome, now() + interval '2 minutes');
  DELETE FROM consult.launch_codes WHERE expires_at < now() - interval '1 day';

  RETURN QUERY SELECT v_code, m.outcome, NULL::text;
END;
$$;

-- ---------------------------------------------------------------- direct path (Budibase /dolphin)
--
-- The Dolphin button opens  …/consult#/dolphin?g=…&i=…&f=…&l=…&b=…  in Chrome; the screen
-- passes those values and the signed-in user's email here. The user must be an active member of
-- a practice with Consult and the Dolphin link switched on. Matching is exactly as above.
-- destination follows the patient list: /review when the patient has a consult, else /intake.

CREATE OR REPLACE FUNCTION consult.dolphin_open(
  p_email      text,
  p_guid       text,
  p_dolphin_id text,
  p_first      text,
  p_last       text,
  p_birthday   text
)
RETURNS TABLE (patient_id bigint, patient_name text, destination text, outcome text, reason text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, consult, public
AS $$
DECLARE
  v_practices uuid[];
  m           record;
BEGIN
  SELECT array_agg(DISTINCT pu.practice_id) INTO v_practices
    FROM public.practice_users pu
    JOIN consult.practice_settings ps ON ps.practice_id = pu.practice_id
   WHERE lower(pu.email) = lower(btrim(COALESCE(p_email, '')))
     AND pu.active AND ps.consult_enabled AND ps.dolphin_linked;

  IF cardinality(v_practices) IS DISTINCT FROM 1 THEN
    RETURN QUERY SELECT NULL::bigint, NULL::text, NULL::text, NULL::text,
      CASE WHEN v_practices IS NULL THEN 'Dolphin link is off for your practice, or your account is not active'
           ELSE 'your account belongs to more than one Dolphin-linked practice' END;
    RETURN;
  END IF;

  SELECT * INTO m FROM consult.dolphin_match(v_practices[1], p_guid, p_dolphin_id, p_first, p_last, p_birthday,
                                             lower(btrim(p_email)));
  IF m.patient_id IS NULL THEN
    RETURN QUERY SELECT NULL::bigint, NULL::text, NULL::text, NULL::text, m.reason;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT p.id,
         p.first_name || ' ' || p.last_name,
         CASE WHEN EXISTS (SELECT 1 FROM consult.consults c WHERE c.patient_id = p.id)
              THEN '/review' ELSE '/intake' END,
         m.outcome,
         NULL::text
    FROM consult.patients p
   WHERE p.id = m.patient_id;
END;
$$;

REVOKE ALL ON FUNCTION consult.dolphin_open(text, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION consult.dolphin_open(text, text, text, text, text, text) TO consult_app;

-- Check: should list dolphin_launch, dolphin_match, dolphin_open
SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'consult' AND p.proname LIKE 'dolphin_%' ORDER BY 1;

-- END OF 03_dolphin_open.sql
