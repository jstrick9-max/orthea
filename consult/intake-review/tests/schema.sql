-- Copy of the live columns these queries touch (from information_schema + the queries themselves).
CREATE SCHEMA consult;
CREATE TABLE public.practice_users (email text, practice_id uuid, role text DEFAULT 'staff', active boolean DEFAULT true);
CREATE TABLE public.doctors (id uuid PRIMARY KEY, practice_id uuid, display_name text, role text, active boolean DEFAULT true);
CREATE TABLE consult.referring_doctors (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, practice_id uuid, full_name text,
  first_name text, practice_name text, email text, mailing_address text);
CREATE TABLE consult.patients (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, practice_id uuid NOT NULL,
  dolphin_patient_id text, dolphin_guid text, first_name text NOT NULL, last_name text NOT NULL, dob date,
  parent1_first_name text, parent2_first_name text, parent1_last_name text, parent2_last_name text,
  mailing_address text, referring_doctor_id bigint, archived_at timestamptz, created_at timestamptz DEFAULT now());
CREATE TABLE consult.consults (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, practice_id uuid NOT NULL, patient_id bigint NOT NULL,
  doctor_id uuid NOT NULL, consult_date date NOT NULL, consult_type text, tmt_notes text, transcript text, structured_record jsonb,
  conflicts jsonb, status text NOT NULL, created_by text, approved_by text, approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(), updated_at timestamptz NOT NULL DEFAULT now(),
  flags_reviewed boolean NOT NULL DEFAULT false, flags_reviewed_by text, flags_reviewed_at timestamptz,
  notes_edited boolean NOT NULL DEFAULT false, download_token text, composite_image text, composite_url text,
  fee_total numeric, fee_initial numeric, fee_monthly numeric, fee_months integer, letter_slots jsonb);
CREATE TABLE consult.outputs (consult_id bigint, output_type text, draft_text text, final_text text);
CREATE TABLE consult.audit_log (consult_id text, action text, actor text, at timestamptz DEFAULT now());
INSERT INTO public.practice_users VALUES ('lso@x.com','11111111-1111-1111-1111-111111111111','staff',true),
                                         ('other@x.com','22222222-2222-2222-2222-222222222222','staff',true);
INSERT INTO public.doctors VALUES ('60758cb2-92c4-4e2b-8c0f-9600518d7227','11111111-1111-1111-1111-111111111111','Dr. Marc','Doctor',true);
INSERT INTO consult.referring_doctors (practice_id, full_name, first_name, mailing_address) VALUES
  ('11111111-1111-1111-1111-111111111111','Dr. Kim Park','Kim','1 Dental Way'),
  ('22222222-2222-2222-2222-222222222222','Dr. Other','O','elsewhere');
INSERT INTO consult.patients (practice_id, dolphin_patient_id, dolphin_guid, first_name, last_name, parent1_first_name) VALUES
  ('11111111-1111-1111-1111-111111111111','221290','{AAAA}','nexa','testa',NULL),
  ('11111111-1111-1111-1111-111111111111',NULL,NULL,'Hand','Made','Ann');
