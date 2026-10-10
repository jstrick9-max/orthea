-- Orthea Consult — Dolphin launch, update to consult.redeem_launch (run after 01).
-- Run ONCE in Beekeeper on the admin connection (the same one you ran 01 on), Auto Commit.
-- Change: the same user may open a launch link again within 30 seconds (Budibase can run a
-- screen's on-load actions twice). Codes stay single-use for everyone else.

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

REVOKE ALL ON FUNCTION consult.redeem_launch(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION consult.redeem_launch(text, text) TO consult_app;
