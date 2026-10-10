-- Run after stub_schema.sql + ../01_dolphin_launch.sql (see run.sh). Stops on the first failure.
\set ON_ERROR_STOP 1
\set QUIET 1
SET ROLE orthea_admin;
INSERT INTO public.practices VALUES ('11111111-1111-1111-1111-111111111111','LSO','lso'), ('22222222-2222-2222-2222-222222222222','Other','other');
INSERT INTO consult.practice_settings VALUES ('11111111-1111-1111-1111-111111111111', true), ('22222222-2222-2222-2222-222222222222', true);
UPDATE consult.practice_settings SET dolphin_linked = true WHERE practice_id = '11111111-1111-1111-1111-111111111111';
INSERT INTO public.practice_users (email, practice_id, active) VALUES
  ('staff@lso.com','11111111-1111-1111-1111-111111111111',true),
  ('gone@lso.com','11111111-1111-1111-1111-111111111111',false),
  ('other@b.com','22222222-2222-2222-2222-222222222222',true);
INSERT INTO consult.patients (practice_id, first_name, last_name, dob, dolphin_patient_id, dolphin_guid, archived_at, mailing_address) VALUES
  ('11111111-1111-1111-1111-111111111111','Leo','Marsh','2014-04-22',NULL,NULL,NULL,'1 Main St'),    -- made by hand
  ('11111111-1111-1111-1111-111111111111','Ava','Stone','2013-02-02','STONE01',NULL,NULL,NULL),
  ('11111111-1111-1111-1111-111111111111','Mia','Ray','2012-03-03','RAY01','{AAAAAAAA-0000-0000-0000-000000000001}',now(),NULL),
  ('11111111-1111-1111-1111-111111111111','Sam','Lee','2015-01-01',NULL,NULL,NULL,NULL),
  ('11111111-1111-1111-1111-111111111111','Sam','Lee','2015-01-01',NULL,NULL,NULL,NULL);
INSERT INTO consult.consults (practice_id, patient_id, status) SELECT practice_id, id, 'review' FROM consult.patients WHERE first_name='Leo';
SELECT consult.create_launch_key('11111111-1111-1111-1111-111111111111','LSO test') AS key_a \gset
SELECT consult.create_launch_key('22222222-2222-2222-2222-222222222222','Other test') AS key_b \gset
RESET ROLE;
SET ROLE consult_app;

-- 1-2. refused: wrong key; practice not Dolphin-linked; no ids
SELECT (code IS NULL AND reason LIKE 'key not recognised%') AS ok FROM consult.dolphin_launch('olk_wrong','{X}','X','A','B','01/01/2015') \gset
\if :ok \echo ok  wrong key refused \else \echo FAIL wrong key \quit \endif
SELECT (code IS NULL) AS ok FROM consult.dolphin_launch(:'key_b','{X}','X','A','B','01/01/2015') \gset
\if :ok \echo ok  practice without Dolphin link refused \else \echo FAIL unlinked practice \quit \endif
SELECT (code IS NULL AND reason = 'no Dolphin patient GUID or ID') AS ok FROM consult.dolphin_launch(:'key_a','','  ','A','B','01/01/2015') \gset
\if :ok \echo ok  launch without GUID or ID refused \else \echo FAIL no ids \quit \endif

-- 3-4. new patient → created, /intake, code works once
SELECT code AS c, outcome AS o FROM consult.dolphin_launch(:'key_a','{8DEB5881-00BC-4F30-8BCF-798E892B9602}','TESTER','Test','Patient','07/15/1987') \gset
SELECT (:'o' = 'created' AND length(:'c') = 64) AS ok \gset
\if :ok \echo ok  new patient created, 64-char code \else \echo FAIL create :o \quit \endif
SELECT (destination = '/intake' AND patient_name = 'Test Patient') AS ok FROM consult.redeem_launch(:'c','Staff@LSO.com ') \gset
\if :ok \echo ok  redeem → /intake for a patient with no consult \else \echo FAIL redeem new \quit \endif
SELECT count(*) = 1 AS ok FROM consult.redeem_launch(:'c','staff@lso.com') \gset
\if :ok \echo ok  same user can repeat within 30 seconds (Budibase double load) \else \echo FAIL repeat \quit \endif
RESET ROLE; SET ROLE orthea_admin;
UPDATE consult.launch_codes SET used_at = now() - interval '31 seconds' WHERE used_at IS NOT NULL;
INSERT INTO public.practice_users (email, practice_id, active) VALUES ('staff2@lso.com','11111111-1111-1111-1111-111111111111',true);
RESET ROLE; SET ROLE consult_app;
SELECT count(*) = 0 AS ok FROM consult.redeem_launch(:'c','staff@lso.com') \gset
\if :ok \echo ok  code cannot be used again after 30 seconds \else \echo FAIL reuse \quit \endif
SELECT (dob = '1987-07-15' AND dolphin_guid = '{8DEB5881-00BC-4F30-8BCF-798E892B9602}') AS ok FROM consult.patients WHERE dolphin_patient_id='TESTER' \gset
\if :ok \echo ok  birthday MM/DD/YYYY stored as a date, GUID stored with braces \else \echo FAIL stored values \quit \endif

-- 5. hand-made patient matched by name + birthday, linked, → /review
SELECT code AS c, outcome AS o FROM consult.dolphin_launch(:'key_a','{BBBBBBBB-0000-0000-0000-000000000002}','DEMO-1002','leo','MARSH','04/22/2014') \gset
SELECT (:'o' = 'name_dob') AS ok \gset
\if :ok \echo ok  hand-made patient matched by name + birthday \else \echo FAIL name_dob :o \quit \endif
SELECT (destination = '/review') AS ok FROM consult.redeem_launch(:'c','staff@lso.com') \gset
\if :ok \echo ok  redeem → /review for a patient with a consult \else \echo FAIL review dest \quit \endif
SELECT (count(*) = 1) AS ok FROM consult.patients WHERE dolphin_patient_id='DEMO-1002' AND dolphin_guid='{BBBBBBBB-0000-0000-0000-000000000002}' AND first_name='leo' AND mailing_address='1 Main St' \gset
\if :ok \echo ok  linked to Dolphin, name follows Dolphin, address kept \else \echo FAIL link \quit \endif

-- 6. next click: GUID match (lower case, no braces); blank last name does not overwrite
SELECT outcome AS o FROM consult.dolphin_launch(:'key_a','bbbbbbbb-0000-0000-0000-000000000002','DEMO-1002','Leo','','') \gset
SELECT (:'o' = 'guid') AS ok \gset
\if :ok \echo ok  GUID match ignores case and braces \else \echo FAIL guid :o \quit \endif
SELECT (first_name='Leo' AND last_name='MARSH' AND dob='2014-04-22') AS ok FROM consult.patients WHERE dolphin_patient_id='DEMO-1002' \gset
\if :ok \echo ok  blank values from Dolphin never overwrite \else \echo FAIL blanks \quit \endif

-- 7. Dolphin ID match on a patient without GUID
SELECT outcome AS o FROM consult.dolphin_launch(:'key_a','{CCCCCCCC-0000-0000-0000-000000000003}','STONE01','Ava','Stone','02/02/2013') \gset
SELECT (:'o' = 'dolphin_id') AS ok \gset
\if :ok \echo ok  matched by Dolphin Patient ID \else \echo FAIL dolphin_id :o \quit \endif

-- 8. archived patient comes back
SELECT outcome AS o FROM consult.dolphin_launch(:'key_a','{AAAAAAAA-0000-0000-0000-000000000001}','RAY01','Mia','Ray','03/03/2012') \gset
SELECT (:'o' = 'guid' AND (SELECT archived_at IS NULL FROM consult.patients WHERE dolphin_patient_id='RAY01')) AS ok \gset
\if :ok \echo ok  archived patient un-archived on launch \else \echo FAIL archive \quit \endif

-- 9. two hand-made matches → no guessing, new patient
SELECT outcome AS o FROM consult.dolphin_launch(:'key_a','{DDDDDDDD-0000-0000-0000-000000000004}','LEE01','Sam','Lee','01/01/2015') \gset
SELECT (:'o' = 'created' AND (SELECT count(*) FROM consult.patients WHERE first_name='Sam') = 3) AS ok \gset
\if :ok \echo ok  ambiguous name + birthday → new patient, no guessing \else \echo FAIL ambiguous :o \quit \endif

-- 10. bad birthdays ignored
SELECT outcome AS o FROM consult.dolphin_launch(:'key_a','{EEEEEEEE-0000-0000-0000-000000000005}','BAD01','Bo','Day','02/31/2015') \gset
SELECT (SELECT dob IS NULL FROM consult.patients WHERE dolphin_patient_id='BAD01') AS ok \gset
\if :ok \echo ok  impossible date 02/31/2015 not stored \else \echo FAIL bad date \quit \endif

-- 10b. a used code is not available to a colleague either
SELECT code AS c2 FROM consult.dolphin_launch(:'key_a','{8DEB5881-00BC-4F30-8BCF-798E892B9602}','TESTER','Test','Patient','07/15/1987') \gset
SELECT count(*) = 1 AS ok FROM consult.redeem_launch(:'c2','staff@lso.com') \gset
SELECT count(*) = 0 AS ok2 FROM consult.redeem_launch(:'c2','staff2@lso.com') \gset
\if :ok2 \echo ok  a used code cannot be taken by a colleague \else \echo FAIL colleague \quit \endif

-- 11. redeem: other practice, inactive user, expired
SELECT code AS c FROM consult.dolphin_launch(:'key_a','{8DEB5881-00BC-4F30-8BCF-798E892B9602}','TESTER','Test','Patient','07/15/1987') \gset
SELECT count(*) = 0 AS ok FROM consult.redeem_launch(:'c','other@b.com') \gset
\if :ok \echo ok  user from another practice cannot redeem \else \echo FAIL cross-practice \quit \endif
SELECT count(*) = 0 AS ok FROM consult.redeem_launch(:'c','gone@lso.com') \gset
\if :ok \echo ok  inactive user cannot redeem \else \echo FAIL inactive \quit \endif
RESET ROLE; SET ROLE orthea_admin;
UPDATE consult.launch_codes SET expires_at = now() - interval '1 second' WHERE used_at IS NULL;
RESET ROLE; SET ROLE consult_app;
SELECT count(*) = 0 AS ok FROM consult.redeem_launch(:'c','staff@lso.com') \gset
\if :ok \echo ok  expired code refused \else \echo FAIL expiry \quit \endif

-- 12. consult_app cannot read keys or codes, or make keys
\set ON_ERROR_STOP 0
SELECT 1 FROM consult.launch_codes;
SELECT 1 FROM consult.launch_keys;
SELECT consult.create_launch_key('11111111-1111-1111-1111-111111111111','x');
\set ON_ERROR_STOP 1
\echo ok  (the three "permission denied" errors above are expected)
SELECT count(*) AS n FROM consult.audit_log WHERE actor = 'dolphin' \gset
\echo ok  audit rows written: :n

-- 13. direct path: consult.dolphin_open (practice from the signed-in user, no key)
SELECT (destination = '/intake' AND outcome = 'created' AND patient_name = 'Nina Vale') AS ok
  FROM consult.dolphin_open('Staff@LSO.com', '{FFFFFFFF-0000-0000-0000-000000000006}', 'VALE01', 'Nina', 'Vale', '05/05/2016') \gset
\if :ok \echo ok  open: new patient created, → /intake \else \echo FAIL open create \quit \endif
SELECT (outcome = 'guid' AND patient_id IS NOT NULL) AS ok
  FROM consult.dolphin_open('staff@lso.com', 'ffffffff-0000-0000-0000-000000000006', 'VALE01', 'Nina', 'Vale', '05/05/2016') \gset
\if :ok \echo ok  open: second click (Budibase double load) finds the same patient \else \echo FAIL open repeat \quit \endif
SELECT (count(*) = 1) AS ok FROM consult.patients WHERE dolphin_patient_id = 'VALE01' \gset
\if :ok \echo ok  open: no duplicate patient \else \echo FAIL open duplicate \quit \endif
SELECT (destination = '/review') AS ok FROM consult.dolphin_open('staff@lso.com', '{BBBBBBBB-0000-0000-0000-000000000002}', 'DEMO-1002', 'Leo', 'Marsh', '04/22/2014') \gset
\if :ok \echo ok  open: patient with a consult → /review \else \echo FAIL open review \quit \endif
SELECT (patient_id IS NULL AND reason LIKE 'Dolphin link is off%') AS ok FROM consult.dolphin_open('other@b.com', '{X}', 'X', 'A', 'B', '') \gset
\if :ok \echo ok  open: user of a practice without the Dolphin link refused \else \echo FAIL open other practice \quit \endif
SELECT (patient_id IS NULL) AS ok FROM consult.dolphin_open('gone@lso.com', '{X}', 'X', 'A', 'B', '') \gset
\if :ok \echo ok  open: inactive user refused \else \echo FAIL open inactive \quit \endif
SELECT (patient_id IS NULL AND reason = 'no Dolphin patient GUID or ID') AS ok FROM consult.dolphin_open('staff@lso.com', '', '', 'A', 'B', '') \gset
\if :ok \echo ok  open: no GUID or ID refused \else \echo FAIL open no ids \quit \endif
SELECT (dob = '2016-05-05') AS ok FROM consult.patients WHERE dolphin_patient_id = 'VALE01' \gset
\if :ok \echo ok  open: birthday stored \else \echo FAIL open dob \quit \endif
SELECT (count(*) >= 2) AS ok FROM consult.audit_log WHERE actor = 'staff@lso.com' AND action LIKE 'dolphin launch%' \gset
\if :ok \echo ok  open: audit rows name the staff member \else \echo FAIL open audit \quit \endif
\set ON_ERROR_STOP 0
SELECT * FROM consult.dolphin_match('11111111-1111-1111-1111-111111111111','{Q}','Q','A','B','','x');
\set ON_ERROR_STOP 1
\echo ok  (the "permission denied for function dolphin_match" above is expected)
\echo ALL PASSED
