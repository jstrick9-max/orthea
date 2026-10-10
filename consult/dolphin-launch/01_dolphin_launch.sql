-- Orthea Consult — Dolphin toolbar launch (step 1: database).
-- Run ONCE as orthea_admin in Beekeeper. Touches only the consult schema; Voice is untouched.
-- Safe to re-run: every statement checks before it changes anything. There is no BEGIN/COMMIT,
-- so Beekeeper stays in Auto Commit; if a statement fails, fix the cause and run the file again.
--
-- What it adds
--   consult.practice_settings.dolphin_linked   per-practice switch (off for everyone)
--   consult.launch_keys                         one secret key per practice, stored hashed
--   consult.launch_codes                        one-time codes, stored hashed, 2-minute life
--   consult.dolphin_launch(...)                 n8n (C04) calls this when the Dolphin button is clicked
--   consult.redeem_launch(code, email)          Budibase /launch calls this to open the patient
--   consult.create_launch_key(practice, label)  admin only: makes a practice's key
--
-- The two tables are owned by orthea_admin and consult_app gets no access to them;
-- consult_app can only call the two functions (SECURITY DEFINER).


-- ---------------------------------------------------------------- settings + tables

ALTER TABLE consult.practice_settings
  ADD COLUMN IF NOT EXISTS dolphin_linked boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS consult.launch_keys (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  practice_id uuid NOT NULL,
  key_hash    text NOT NULL UNIQUE,          -- sha256 hex of the key; the key itself is never stored
  label       text,                          -- e.g. 'LSO workstations'
  created_at  timestamptz NOT NULL DEFAULT now(),
  revoked_at  timestamptz
);

CREATE TABLE IF NOT EXISTS consult.launch_codes (
  code_hash   text PRIMARY KEY,              -- sha256 hex of the one-time code
  practice_id uuid NOT NULL,
  patient_id  bigint NOT NULL,
  outcome     text NOT NULL,                 -- how the patient was found: guid / dolphin_id / name_dob / created
  created_at  timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL,
  used_at     timestamptz,
  used_by     text
);

REVOKE ALL ON consult.launch_keys, consult.launch_codes FROM PUBLIC;

-- One Orthea patient per Dolphin patient (GUID), per practice.
-- If this fails with "could not create unique index", two patients already share a
-- GUID: run the check at the bottom of this file, fix them, and run again.
CREATE UNIQUE INDEX IF NOT EXISTS patients_practice_dolphin_guid_key
  ON consult.patients (practice_id, upper(btrim(dolphin_guid, '{} ')))
  WHERE dolphin_guid IS NOT NULL AND btrim(dolphin_guid, '{} ') <> '';

CREATE INDEX IF NOT EXISTS patients_practice_dolphin_id_idx
  ON consult.patients (practice_id, dolphin_patient_id)
  WHERE dolphin_patient_id IS NOT NULL;

-- ---------------------------------------------------------------- helpers

CREATE OR REPLACE FUNCTION consult.launch_hash(p_secret text)
RETURNS text LANGUAGE sql IMMUTABLE STRICT
SET search_path = pg_catalog
AS $$ SELECT encode(sha256(convert_to(p_secret, 'UTF8')), 'hex') $$;

REVOKE ALL ON FUNCTION consult.launch_hash(text) FROM PUBLIC;

-- ---------------------------------------------------------------- launch (called by n8n C04)
--
-- Arguments are the Dolphin toolbar tokens, as text, exactly as the launcher received them:
--   {PatientGUID} {PatientID} {PatientFirstName} {PatientLastName} {PatientBirthday} (MM/DD/YYYY)
-- Returns one row. code is NULL when the launch is refused; reason says why.
--
-- Matching, within the key's practice:
--   1. same Dolphin GUID
--   2. same Dolphin Patient ID, on a patient with no GUID yet (exactly one)
--   3. same first + last name + birthday, on a patient with no Dolphin link yet (exactly one)
--   4. otherwise a new patient is created
-- Dolphin is the master for name and birthday: a match is refreshed from Dolphin,
-- but a blank value from Dolphin never overwrites a filled one. Parents, address,
-- referrer and fees are never touched (staff own them in Letter Details).

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
  v_guid     text := NULLIF(upper(btrim(COALESCE(p_guid, ''), '{} ')), '');
  v_id       text := NULLIF(btrim(COALESCE(p_dolphin_id, '')), '');
  v_first    text := NULLIF(regexp_replace(btrim(COALESCE(p_first, '')), '\s+', ' ', 'g'), '');
  v_last     text := NULLIF(regexp_replace(btrim(COALESCE(p_last, '')), '\s+', ' ', 'g'), '');
  v_dob      date;
  v_patient  bigint;
  v_outcome  text;
  v_code     text;
  v_ids      bigint[];
BEGIN
  -- Practice from the key; the practice must have Consult and the Dolphin link switched on.
  SELECT k.practice_id INTO v_practice
    FROM consult.launch_keys k
    JOIN consult.practice_settings ps ON ps.practice_id = k.practice_id
   WHERE k.key_hash = consult.launch_hash(COALESCE(p_key, ''))
     AND k.revoked_at IS NULL
     AND ps.consult_enabled
     AND ps.dolphin_linked;
  IF v_practice IS NULL THEN
    RETURN QUERY SELECT NULL::text, NULL::text, 'key not recognised, or Dolphin launch is off for this practice';
    RETURN;
  END IF;

  IF v_guid IS NULL AND v_id IS NULL THEN
    RETURN QUERY SELECT NULL::text, NULL::text, 'no Dolphin patient GUID or ID';
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

  -- 1. GUID
  IF v_guid IS NOT NULL THEN
    SELECT p.id INTO v_patient FROM consult.patients p
     WHERE p.practice_id = v_practice
       AND p.dolphin_guid IS NOT NULL
       AND upper(btrim(p.dolphin_guid, '{} ')) = v_guid;
    IF v_patient IS NOT NULL THEN v_outcome := 'guid'; END IF;
  END IF;

  -- 2. Dolphin Patient ID, only on patients not yet tied to a GUID
  IF v_patient IS NULL AND v_id IS NOT NULL THEN
    SELECT array_agg(p.id) INTO v_ids FROM consult.patients p
     WHERE p.practice_id = v_practice
       AND btrim(p.dolphin_patient_id) = v_id
       AND (p.dolphin_guid IS NULL OR btrim(p.dolphin_guid, '{} ') = '');
    IF cardinality(v_ids) = 1 THEN v_patient := v_ids[1]; v_outcome := 'dolphin_id'; END IF;
  END IF;

  -- 3. Name + birthday, only on patients with no Dolphin link at all (e.g. made by hand)
  IF v_patient IS NULL AND v_first IS NOT NULL AND v_last IS NOT NULL AND v_dob IS NOT NULL THEN
    SELECT array_agg(p.id) INTO v_ids FROM consult.patients p
     WHERE p.practice_id = v_practice
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
      RETURN QUERY SELECT NULL::text, NULL::text, 'new patient but Dolphin sent no first or last name';
      RETURN;
    END IF;
    INSERT INTO consult.patients (practice_id, dolphin_guid, dolphin_patient_id, first_name, last_name, dob)
    VALUES (v_practice, CASE WHEN v_guid IS NOT NULL THEN '{' || v_guid || '}' END, v_id, v_first, v_last, v_dob)
    RETURNING id INTO v_patient;
    v_outcome := 'created';
  END IF;

  INSERT INTO consult.audit_log (consult_id, action, actor)
  VALUES ('patient:' || v_patient, 'dolphin launch (' || v_outcome || ')', 'dolphin');

  -- One-time code: 64 random hex characters, stored only as a hash.
  v_code := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  INSERT INTO consult.launch_codes (code_hash, practice_id, patient_id, outcome, expires_at)
  VALUES (consult.launch_hash(v_code), v_practice, v_patient, v_outcome, now() + interval '2 minutes');

  DELETE FROM consult.launch_codes WHERE expires_at < now() - interval '1 day';

  RETURN QUERY SELECT v_code, v_outcome, NULL::text;
END;
$$;

-- ---------------------------------------------------------------- redeem (called by Budibase /launch)
--
-- Swaps a code for the patient, once, for a signed-in user of the same practice
-- (the same user may repeat it within 30 seconds).
-- destination follows the patient list: /review when the patient has a consult, else /intake.
-- No row = code unknown, used, expired, or for another practice.

CREATE OR REPLACE FUNCTION consult.redeem_launch(p_code text, p_email text)
RETURNS TABLE (patient_id bigint, patient_name text, destination text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, consult, public
AS $$
DECLARE
  v_patient bigint;
BEGIN
  -- Single use. The same user may open it again within 30 seconds, because Budibase can
  -- run a screen's on-load actions twice; nobody else ever can.
  UPDATE consult.launch_codes lc
     SET used_at = COALESCE(lc.used_at, now()), used_by = lower(btrim(p_email))
   WHERE lc.code_hash = consult.launch_hash(btrim(COALESCE(p_code, '')))
     AND (lc.used_at IS NULL
          OR (lc.used_by = lower(btrim(p_email)) AND lc.used_at > now() - interval '30 seconds'))
     AND lc.expires_at > now()
     AND lc.practice_id IN (SELECT pu.practice_id FROM public.practice_users pu
                             WHERE lower(pu.email) = lower(btrim(p_email)) AND pu.active)
  RETURNING lc.patient_id INTO v_patient;

  IF v_patient IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT p.id,
         p.first_name || ' ' || p.last_name,
         CASE WHEN EXISTS (SELECT 1 FROM consult.consults c WHERE c.patient_id = p.id)
              THEN '/review' ELSE '/intake' END
    FROM consult.patients p
   WHERE p.id = v_patient;
END;
$$;

-- ---------------------------------------------------------------- admin: make a practice's key
--
-- SELECT consult.create_launch_key('<practice uuid>', 'LSO workstations');
-- Copy the key it returns into the launcher's settings now: it can't be shown again.
-- To retire a key: UPDATE consult.launch_keys SET revoked_at = now() WHERE id = …;

CREATE OR REPLACE FUNCTION consult.create_launch_key(p_practice_id uuid, p_label text)
RETURNS text LANGUAGE plpgsql
SET search_path = pg_catalog, consult, public
AS $$
DECLARE v_key text := 'olk_' || replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
BEGIN
  INSERT INTO consult.launch_keys (practice_id, key_hash, label)
  VALUES (p_practice_id, consult.launch_hash(v_key), p_label);
  RETURN v_key;
END;
$$;

-- ---------------------------------------------------------------- permissions

REVOKE ALL ON FUNCTION consult.dolphin_launch(text, text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION consult.redeem_launch(text, text)                         FROM PUBLIC;
REVOKE ALL ON FUNCTION consult.create_launch_key(uuid, text)                     FROM PUBLIC;
GRANT EXECUTE ON FUNCTION consult.dolphin_launch(text, text, text, text, text, text) TO consult_app;
GRANT EXECUTE ON FUNCTION consult.redeem_launch(text, text)                         TO consult_app;


-- ---------------------------------------------------------------- checks (read-only)

-- Practices and their switches:
SELECT p.name, ps.consult_enabled, ps.dolphin_linked
  FROM consult.practice_settings ps JOIN public.practices p ON p.id = ps.practice_id;

-- Patients sharing a Dolphin GUID or ID (should be none):
SELECT practice_id, upper(btrim(dolphin_guid, '{} ')) AS guid, count(*)
  FROM consult.patients WHERE dolphin_guid IS NOT NULL
 GROUP BY 1, 2 HAVING count(*) > 1;
SELECT practice_id, dolphin_patient_id, count(*)
  FROM consult.patients WHERE dolphin_patient_id IS NOT NULL
 GROUP BY 1, 2 HAVING count(*) > 1;
