\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned
INSERT INTO public.practices VALUES ('11111111-1111-1111-1111-111111111111','Lemchen Salzer','lso'),
                                    ('22222222-2222-2222-2222-222222222222','Bronsky','bronsky');
INSERT INTO inbox.addresses VALUES ('lso.inbox@ortheasecurity.com','11111111-1111-1111-1111-111111111111'),
                                   ('bronsky.inbox@ortheasecurity.com','22222222-2222-2222-2222-222222222222');
INSERT INTO inbox.senders (practice_id, email, display_name) VALUES
  ('11111111-1111-1111-1111-111111111111','drl@lso.com','Dr. Lemchen'),
  ('11111111-1111-1111-1111-111111111111','old@lso.com','Old');
UPDATE inbox.senders SET active = false WHERE email = 'old@lso.com';
INSERT INTO consult.patients (practice_id, first_name, last_name, dob) VALUES
  ('11111111-1111-1111-1111-111111111111','Leo','Marsh','2013-08-27'),
  ('11111111-1111-1111-1111-111111111111','Owen','Hale','2017-04-14'),
  ('11111111-1111-1111-1111-111111111111','Ava','Reyes','2014-03-12'),
  ('11111111-1111-1111-1111-111111111111','Ava','Reyes','2016-01-01'),
  ('22222222-2222-2222-2222-222222222222','Leo','Marsh','2013-08-27');

SET ROLE consult_app;

-- receive
SELECT (status = 'processing' AND approved AND NOT duplicate) AS ok
  FROM inbox.receive('LSO.Inbox@ortheasecurity.com', '<m1@x>', 'DrL@LSO.com', 'Dr L', 'Leo', 'note',
                     '[{"kind":"audio","name":"a.m4a"}]') \gset
\if :ok \echo ok  approved sender, address in any case → processing \else \echo FAIL receive \quit \endif
SELECT (duplicate AND status = 'processing') AS ok FROM inbox.receive('lso.inbox@ortheasecurity.com', '<m1@x>', 'drl@lso.com', '', '', '', '[]') \gset
\if :ok \echo ok  same Message-ID again → not stored twice \else \echo FAIL dup \quit \endif
SELECT (status = 'held' AND NOT approved) AS ok FROM inbox.receive('lso.inbox@ortheasecurity.com', '<m2@x>', 'stranger@gmail.com', '', 'hi', '', '[]') \gset
\if :ok \echo ok  unknown sender → held \else \echo FAIL stranger \quit \endif
SELECT (status = 'held') AS ok FROM inbox.receive('lso.inbox@ortheasecurity.com', '<m3@x>', 'old@lso.com', '', '', '', '[]') \gset
\if :ok \echo ok  deactivated sender → held \else \echo FAIL inactive \quit \endif
SELECT count(*) = 0 AS ok FROM inbox.receive('someone@ortheasecurity.com', '<m4@x>', 'drl@lso.com', '', '', '', '[]') \gset
\if :ok \echo ok  not an inbox address → nothing stored \else \echo FAIL address \quit \endif
SELECT (status = 'processing') AS ok FROM inbox.receive('cc@x.com, lso.inbox@ortheasecurity.com', '<m5@x>', 'drl@lso.com', '', '', '', '[]') \gset
\if :ok \echo ok  inbox address among several To addresses \else \echo FAIL multi-to \quit \endif
SELECT (status = 'held') AS ok FROM inbox.receive('bronsky.inbox@ortheasecurity.com', '<m6@x>', 'drl@lso.com', '', '', '', '[]') \gset
\if :ok \echo ok  LSO sender is not approved for another practice \else \echo FAIL cross-practice \quit \endif

-- complete + matching
SELECT id AS m1 FROM inbox.items WHERE message_id = '<m1@x>' \gset
SELECT (match = 'name_dob' AND patient_id IS NOT NULL) AS ok
  FROM inbox.complete(:m1, 'Transcript', 'Summary', 'Note', ' leo ', 'MARSH', '08/27/2013', '') \gset
\if :ok \echo ok  name + birthday match (case/space-insensitive), own practice only \else \echo FAIL name_dob \quit \endif
SELECT (p.practice_id = '11111111-1111-1111-1111-111111111111') AS ok FROM inbox.items i JOIN consult.patients p ON p.id = i.patient_id WHERE i.id = :m1 \gset
RESET ROLE;
SELECT (p.practice_id = '11111111-1111-1111-1111-111111111111' AND i.status = 'new' AND i.chart_note = 'Note') AS ok
  FROM inbox.items i JOIN consult.patients p ON p.id = i.patient_id WHERE i.id = :m1 \gset
\if :ok \echo ok  matched within LSO, status new, note stored \else \echo FAIL stored \quit \endif
SET ROLE consult_app;
SELECT count(*) = 0 AS ok FROM inbox.complete(:m1, 'x', 'x', 'x', 'Owen', 'Hale', '', '') \gset
\if :ok \echo ok  a finished item is not reprocessed \else \echo FAIL rerun \quit \endif

SELECT id AS m5 FROM inbox.items WHERE message_id = '<m5@x>' \gset
SELECT (match = 'name') AS ok FROM inbox.complete(:m5, 't', 's', 'n', 'Owen', 'Hale', '', '') \gset
\if :ok \echo ok  name only, one such patient → matched \else \echo FAIL name \quit \endif

RESET ROLE;
INSERT INTO inbox.items (practice_id, message_id, to_address, from_email, status) VALUES
  ('11111111-1111-1111-1111-111111111111','<a1>','lso.inbox@ortheasecurity.com','drl@lso.com','processing'),
  ('11111111-1111-1111-1111-111111111111','<a2>','lso.inbox@ortheasecurity.com','drl@lso.com','processing'),
  ('11111111-1111-1111-1111-111111111111','<a3>','lso.inbox@ortheasecurity.com','drl@lso.com','processing'),
  ('11111111-1111-1111-1111-111111111111','<a4>','lso.inbox@ortheasecurity.com','drl@lso.com','processing');
SET ROLE consult_app;
SELECT (match = 'none' AND patient_id IS NULL) AS ok FROM inbox.complete((SELECT id FROM inbox.items WHERE message_id='<a1>'), 't','s','n','Ava','Reyes','','') \gset
\if :ok \echo ok  two patients with that name and no birthday → left for staff to pick \else \echo FAIL ambiguous \quit \endif
SELECT (match = 'name_dob') AS ok FROM inbox.complete((SELECT id FROM inbox.items WHERE message_id='<a2>'), 't','s','n','Ava','Reyes','2016-01-01','') \gset
\if :ok \echo ok  …and the birthday picks the right one \else \echo FAIL ambiguous dob \quit \endif
SELECT (match = 'last_dob') AS ok FROM inbox.complete((SELECT id FROM inbox.items WHERE message_id='<a3>'), 't','s','n','Leonard','Marsh','2013-08-27','') \gset
\if :ok \echo ok  nickname/first-name mismatch, last name + birthday → matched \else \echo FAIL last_dob \quit \endif
SELECT (status = 'error') AS ok FROM inbox.complete((SELECT id FROM inbox.items WHERE message_id='<a4>'), '','','','','','','transcription failed') \gset
\if :ok \echo ok  an error is recorded, not shown as a note \else \echo FAIL error \quit \endif
SELECT count(*) = 0 AS ok FROM inbox.complete((SELECT id FROM inbox.items WHERE message_id='<m2@x>'), 't','s','n','Leo','Marsh','','') \gset
\if :ok \echo ok  a held message (unknown sender) is never processed \else \echo FAIL held processed \quit \endif

-- what n8n / Budibase may not do
\set ON_ERROR_STOP 0
DELETE FROM inbox.items;
INSERT INTO inbox.senders VALUES ('11111111-1111-1111-1111-111111111111','evil@x.com','x');
UPDATE inbox.items SET transcript = 'changed';
\set ON_ERROR_STOP 1
\echo ok  (the three "permission denied" errors above are expected)
RESET ROLE;
SELECT count(*) = 0 AS ok FROM inbox.senders WHERE email = 'evil@x.com' \gset
\if :ok \echo ok  app role cannot add approved senders \else \echo FAIL senders writable \quit \endif
\echo ALL PASSED
