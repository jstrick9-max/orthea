-- Orthea Consult — composite photo from the Letter Details card.
-- Run ONCE as orthea_admin. Touches only the consult schema.
--
-- consult.wait_for_composite(consult_id, max_seconds) checks once a second and returns as
-- soon as the photo has been fetched (composite_image filled) or removed (composite_url
-- empty), or after max_seconds (capped at 12, under Budibase's ~15 s query limit).
-- Returns 'ready', 'none' or 'loading'.

CREATE OR REPLACE FUNCTION consult.wait_for_composite(p_consult_id bigint, p_max_seconds int DEFAULT 12)
RETURNS text
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  img_ready boolean;
  has_url   boolean;
  deadline  timestamptz := clock_timestamp()
                           + make_interval(secs => LEAST(GREATEST(COALESCE(p_max_seconds, 12), 1), 12));
BEGIN
  LOOP
    SELECT c.composite_image IS NOT NULL, c.composite_url IS NOT NULL
      INTO img_ready, has_url
      FROM consult.consults c WHERE c.id = p_consult_id;
    IF img_ready THEN RETURN 'ready'; END IF;
    IF NOT COALESCE(has_url, false) THEN RETURN 'none'; END IF;
    EXIT WHEN clock_timestamp() >= deadline;
    PERFORM pg_sleep(1);
  END LOOP;
  RETURN 'loading';
END
$$;

GRANT EXECUTE ON FUNCTION consult.wait_for_composite(bigint, int) TO consult_app;
