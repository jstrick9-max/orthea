-- Orthea Inbox — set the real password and senders (00 and 02 were run with the placeholders).
-- Beekeeper, admin connection, Auto Commit.
-- 1. Replace NEW-STRONG-PASSWORD (password manager).
-- 2. Replace the example address with the one(s) you'll send test notes from; add a line per person.

ALTER ROLE inbox_app PASSWORD 'NEW-STRONG-PASSWORD';

DELETE FROM inbox.senders WHERE email = 'your.email@example.com';

INSERT INTO inbox.senders (practice_id, email, display_name)
SELECT p.id, lower(s.email), s.name
  FROM public.practices p,
       (VALUES ('you@example.com', 'Your name')
       ) AS s(email, name)
 WHERE p.name ILIKE '%Lemchen%'
ON CONFLICT (practice_id, email) DO UPDATE SET display_name = EXCLUDED.display_name, active = true;

-- Check: no example.com address left, yours listed
SELECT email, display_name, active FROM inbox.senders ORDER BY email;
-- END OF 03_fix_setup.sql
