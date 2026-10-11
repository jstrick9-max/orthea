-- Orthea Inbox — connect LSO's inbox address and approved senders. Run after 01_inbox.sql.
-- Beekeeper, admin connection, Auto Commit. Safe to re-run.
-- Edit the sender list first: one line per person allowed to send to the inbox.

INSERT INTO inbox.addresses (address, practice_id)
SELECT 'lso.inbox@ortheasecurity.com', id FROM public.practices WHERE name ILIKE '%Lemchen%'
ON CONFLICT (address) DO NOTHING;

INSERT INTO inbox.senders (practice_id, email, display_name)
SELECT p.id, lower(s.email), s.name
  FROM public.practices p,
       (VALUES ('lso@ortheasecurity.com',     'LSO office'),
               ('YOUR.EMAIL@example.com',     'Your name')        -- replace or delete this line
       ) AS s(email, name)
 WHERE p.name ILIKE '%Lemchen%'
ON CONFLICT (practice_id, email) DO UPDATE SET display_name = EXCLUDED.display_name, active = true;

-- Check: one address, your senders
SELECT a.address, pr.name FROM inbox.addresses a JOIN public.practices pr ON pr.id = a.practice_id;
SELECT email, display_name, active FROM inbox.senders ORDER BY email;
-- END OF 02_lso_setup.sql
