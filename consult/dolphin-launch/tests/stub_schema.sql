-- Minimal copy of the live tables the launch touches (columns from information_schema, 2026-10-09).
CREATE ROLE orthea_admin LOGIN; CREATE ROLE consult_app LOGIN;
CREATE SCHEMA consult AUTHORIZATION orthea_admin;
GRANT USAGE ON SCHEMA consult TO consult_app;
GRANT CREATE ON SCHEMA public TO orthea_admin;
SET ROLE orthea_admin;
CREATE TABLE public.practices (id uuid PRIMARY KEY, name text NOT NULL, slug text NOT NULL, status text NOT NULL DEFAULT 'active');
CREATE TABLE public.practice_users (email text NOT NULL, practice_id uuid NOT NULL, role text NOT NULL DEFAULT 'staff', active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE consult.practice_settings (practice_id uuid PRIMARY KEY, consult_enabled boolean NOT NULL DEFAULT false);
CREATE TABLE consult.patients (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, practice_id uuid NOT NULL,
  dolphin_patient_id text, dolphin_guid text, first_name text NOT NULL, last_name text NOT NULL, dob date,
  parent1_first_name text, parent2_first_name text, referring_doctor_id bigint, created_at timestamptz NOT NULL DEFAULT now(),
  parent1_last_name text, parent2_last_name text, mailing_address text, archived_at timestamptz);
CREATE TABLE consult.consults (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, practice_id uuid NOT NULL, patient_id bigint NOT NULL,
  status text NOT NULL DEFAULT 'draft', created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE consult.audit_log (id bigint GENERATED ALWAYS AS IDENTITY, consult_id text, action text, actor text, at timestamptz DEFAULT now());
GRANT SELECT, INSERT, UPDATE ON consult.patients, consult.consults, consult.audit_log, consult.practice_settings TO consult_app;
GRANT SELECT ON public.practice_users, public.practices TO consult_app;
RESET ROLE;
