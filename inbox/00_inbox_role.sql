-- Orthea Inbox — its own database user. Run FIRST, once, in Beekeeper on the admin connection.
-- 1. Replace CHANGE-ME with a new strong password (keep it in your password manager; it goes
--    into the Inbox Budibase datasource and the n8n credential, nowhere else).
-- 2. Run. If it says "permission denied to create role", run it on the RDS master connection.

CREATE ROLE inbox_app LOGIN PASSWORD 'CHANGE-ME';

-- Check
SELECT rolname, rolcanlogin FROM pg_roles WHERE rolname = 'inbox_app';
-- END OF 00_inbox_role.sql
