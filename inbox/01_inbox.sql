-- Orthea Inbox — database (demo build).
-- Run ONCE in Beekeeper on the admin connection, Auto Commit. Safe to re-run.
-- Check the editor ends with the line  -- END OF 01_inbox.sql  before Run All.
--
-- Doctors forward a voice note / photo / text to their practice's inbox address
-- (LSO: lso.inbox@ortheasecurity.com). n8n reads the mailbox and calls
--   inbox.receive(...)   store the message (once), decide practice + approved sender
--   inbox.complete(...)  add transcript, summary, chart note, and match the patient
-- Staff then review it in Budibase and copy the chart note into the practice's chart.
-- Orthea never writes to Dolphin.

CREATE SCHEMA IF NOT EXISTS inbox;

-- Which inbox address belongs to which practice
CREATE TABLE IF NOT EXISTS inbox.addresses (
  address     text PRIMARY KEY CHECK (address = lower(address)),
  practice_id uuid NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Who may send to a practice's inbox. Mail from anyone else is held, not processed.
CREATE TABLE IF NOT EXISTS inbox.senders (
  practice_id  uuid NOT NULL,
  email        text NOT NULL CHECK (email = lower(email)),
  display_name text,
  active       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (practice_id, email)
);

CREATE TABLE IF NOT EXISTS inbox.items (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  practice_id   uuid NOT NULL,
  message_id    text NOT NULL,                 -- the email's Message-ID: a message is stored once
  received_at   timestamptz NOT NULL DEFAULT now(),
  to_address    text NOT NULL,
  from_email    text NOT NULL,
  from_name     text,
  subject       text,
  body_text     text,
  attachments   jsonb NOT NULL DEFAULT '[]',   -- [{kind: audio|image|file, name, mime, size, url}]
  status        text NOT NULL DEFAULT 'processing'
                CHECK (status IN ('processing', 'new', 'held', 'filed', 'dismissed', 'error')),
  transcript    text,
  summary       text,
  chart_note    text,
  said_first    text,                          -- the patient as the message names them
  said_last     text,
  said_dob      date,
  patient_id    bigint,
  match         text CHECK (match IN ('name_dob', 'name', 'last_dob', 'manual', 'none')),
  error         text,
  filed_by      text,
  filed_at      timestamptz,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (practice_id, message_id)
);
CREATE INDEX IF NOT EXISTS items_practice_status ON inbox.items (practice_id, status, received_at DESC);
CREATE INDEX IF NOT EXISTS items_patient ON inbox.items (patient_id);

-- ---------------------------------------------------------------- receive

CREATE OR REPLACE FUNCTION inbox.receive(
  p_to          text,
  p_message_id  text,
  p_from_email  text,
  p_from_name   text,
  p_subject     text,
  p_body        text,
  p_attachments jsonb
)
RETURNS TABLE (item_id bigint, status text, approved boolean, duplicate boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, inbox, public
AS $$
DECLARE
  v_practice uuid;
  v_from     text := lower(btrim(COALESCE(p_from_email, '')));
  v_msg      text := NULLIF(btrim(COALESCE(p_message_id, '')), '');
  v_ok       boolean;
  v_id       bigint;
BEGIN
  -- the first of the To addresses that is an inbox address
  SELECT a.practice_id INTO v_practice
    FROM inbox.addresses a
   WHERE a.address = ANY (regexp_split_to_array(lower(COALESCE(p_to, '')), '\s*[,;]\s*'))
   LIMIT 1;
  IF v_practice IS NULL THEN
    RETURN;                                     -- not an inbox address: nothing stored
  END IF;
  IF v_msg IS NULL THEN
    v_msg := md5(COALESCE(p_from_email, '') || COALESCE(p_subject, '') || COALESCE(p_body, '') || clock_timestamp()::text);
  END IF;

  SELECT i.id INTO v_id FROM inbox.items i WHERE i.practice_id = v_practice AND i.message_id = v_msg;
  IF v_id IS NOT NULL THEN
    RETURN QUERY SELECT i.id, i.status, (i.status <> 'held'), true FROM inbox.items i WHERE i.id = v_id;
    RETURN;
  END IF;

  v_ok := EXISTS (SELECT 1 FROM inbox.senders s
                   WHERE s.practice_id = v_practice AND s.email = v_from AND s.active);

  INSERT INTO inbox.items (practice_id, message_id, to_address, from_email, from_name, subject, body_text,
                           attachments, status)
  VALUES (v_practice, v_msg, lower(btrim(p_to)), v_from, NULLIF(btrim(p_from_name), ''),
          NULLIF(btrim(p_subject), ''), NULLIF(btrim(p_body), ''),
          COALESCE(p_attachments, '[]'::jsonb), CASE WHEN v_ok THEN 'processing' ELSE 'held' END)
  ON CONFLICT (practice_id, message_id) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN                          -- lost a race with the same message: report it
    RETURN QUERY SELECT i.id, i.status, (i.status <> 'held'), true
                   FROM inbox.items i WHERE i.practice_id = v_practice AND i.message_id = v_msg;
    RETURN;
  END IF;
  RETURN QUERY SELECT v_id, CASE WHEN v_ok THEN 'processing' ELSE 'held' END, v_ok, false;
END;
$$;

-- ---------------------------------------------------------------- complete

CREATE OR REPLACE FUNCTION inbox.complete(
  p_item_id    bigint,
  p_transcript text,
  p_summary    text,
  p_chart_note text,
  p_first      text,
  p_last       text,
  p_dob        text,     -- YYYY-MM-DD or MM/DD/YYYY; anything else is ignored
  p_error      text
)
RETURNS TABLE (item_id bigint, status text, patient_id bigint, match text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, inbox, consult, public
AS $$
DECLARE
  v_item    inbox.items;
  v_first   text := NULLIF(lower(regexp_replace(btrim(COALESCE(p_first, '')), '\s+', ' ', 'g')), '');
  v_last    text := NULLIF(lower(regexp_replace(btrim(COALESCE(p_last, '')), '\s+', ' ', 'g')), '');
  v_dob     date;
  v_ids     bigint[];
  v_patient bigint;
  v_match   text := 'none';
BEGIN
  SELECT * INTO v_item FROM inbox.items i WHERE i.id = p_item_id;
  IF v_item.id IS NULL OR v_item.status <> 'processing' THEN
    RETURN;                                     -- unknown, held, or already done
  END IF;

  IF NULLIF(btrim(COALESCE(p_error, '')), '') IS NOT NULL THEN
    UPDATE inbox.items i SET status = 'error', error = left(btrim(p_error), 2000), updated_at = now()
     WHERE i.id = p_item_id;
    RETURN QUERY SELECT p_item_id, 'error'::text, NULL::bigint, NULL::text;
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

  -- 1. first + last + birthday  2. first + last (exactly one)  3. last + birthday (exactly one)
  IF v_first IS NOT NULL AND v_last IS NOT NULL AND v_dob IS NOT NULL THEN
    SELECT array_agg(p.id) INTO v_ids FROM consult.patients p
     WHERE p.practice_id = v_item.practice_id AND lower(p.first_name) = v_first
       AND lower(p.last_name) = v_last AND p.dob = v_dob;
    IF cardinality(v_ids) = 1 THEN v_patient := v_ids[1]; v_match := 'name_dob'; END IF;
  END IF;
  IF v_patient IS NULL AND v_first IS NOT NULL AND v_last IS NOT NULL THEN
    SELECT array_agg(p.id) INTO v_ids FROM consult.patients p
     WHERE p.practice_id = v_item.practice_id AND lower(p.first_name) = v_first
       AND lower(p.last_name) = v_last AND p.archived_at IS NULL;
    IF cardinality(v_ids) = 1 THEN v_patient := v_ids[1]; v_match := 'name'; END IF;
  END IF;
  IF v_patient IS NULL AND v_last IS NOT NULL AND v_dob IS NOT NULL THEN
    SELECT array_agg(p.id) INTO v_ids FROM consult.patients p
     WHERE p.practice_id = v_item.practice_id AND lower(p.last_name) = v_last AND p.dob = v_dob;
    IF cardinality(v_ids) = 1 THEN v_patient := v_ids[1]; v_match := 'last_dob'; END IF;
  END IF;

  UPDATE inbox.items i
     SET status     = 'new',
         transcript = NULLIF(btrim(COALESCE(p_transcript, '')), ''),
         summary    = NULLIF(btrim(COALESCE(p_summary, '')), ''),
         chart_note = NULLIF(btrim(COALESCE(p_chart_note, '')), ''),
         said_first = NULLIF(btrim(COALESCE(p_first, '')), ''),
         said_last  = NULLIF(btrim(COALESCE(p_last, '')), ''),
         said_dob   = v_dob,
         patient_id = v_patient,
         match      = v_match,
         error      = NULL,
         updated_at = now()
   WHERE i.id = p_item_id;

  RETURN QUERY SELECT p_item_id, 'new'::text, v_patient, v_match;
END;
$$;

-- ---------------------------------------------------------------- access
-- n8n (consult_app) only calls the two functions; Budibase (consult_app) reads and updates items.
REVOKE ALL ON FUNCTION inbox.receive(text, text, text, text, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION inbox.complete(bigint, text, text, text, text, text, text, text) FROM PUBLIC;
GRANT USAGE ON SCHEMA inbox TO consult_app;
GRANT EXECUTE ON FUNCTION inbox.receive(text, text, text, text, text, text, jsonb) TO consult_app;
GRANT EXECUTE ON FUNCTION inbox.complete(bigint, text, text, text, text, text, text, text) TO consult_app;
GRANT SELECT ON inbox.items, inbox.senders, inbox.addresses TO consult_app;
GRANT UPDATE (status, patient_id, match, chart_note, filed_by, filed_at, updated_at) ON inbox.items TO consult_app;

-- Check: the new objects
SELECT 'inbox tables' AS what, count(*) AS n FROM information_schema.tables WHERE table_schema = 'inbox'
UNION ALL
SELECT 'inbox functions', count(*) FROM information_schema.routines WHERE routine_schema = 'inbox';
-- END OF 01_inbox.sql
