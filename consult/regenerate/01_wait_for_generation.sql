-- Orthea Consult — let Budibase wait for n8n to finish generating letters.
-- Run ONCE as orthea_admin. Touches only the consult schema.
--
-- consult.wait_for_generation(consult_id, max_seconds) checks the consult's status
-- once a second and returns as soon as it is no longer 'generating', or after
-- max_seconds (capped at 12, under Budibase's ~15 s query timeout). It returns the
-- status it last saw. Each check sees n8n's committed changes because every
-- statement in a plpgsql function takes a fresh snapshot.

CREATE OR REPLACE FUNCTION consult.wait_for_generation(p_consult_id bigint, p_max_seconds int DEFAULT 12)
RETURNS text
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  s text;
  deadline timestamptz := clock_timestamp()
                          + make_interval(secs => LEAST(GREATEST(COALESCE(p_max_seconds, 12), 1), 12));
BEGIN
  LOOP
    SELECT c.status INTO s FROM consult.consults c WHERE c.id = p_consult_id;
    EXIT WHEN s IS DISTINCT FROM 'generating' OR clock_timestamp() >= deadline;
    PERFORM pg_sleep(1);
  END LOOP;
  RETURN s;
END
$$;

GRANT EXECUTE ON FUNCTION consult.wait_for_generation(bigint, int) TO consult_app;
