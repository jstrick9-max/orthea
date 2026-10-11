#!/bin/sh
# Throwaway Postgres 16 on /tmp/pgt port 5499. Reuses the Dolphin-launch stub schema (roles, practices, patients).
set -e
B=/usr/lib/postgresql/16/bin; D="$(cd "$(dirname "$0")" && pwd)"
P="$B/psql -X -q -v ON_ERROR_STOP=1 -h /tmp/pgt -p 5499"
su postgres -c "$P -U postgres -c 'DROP DATABASE IF EXISTS ib' -c 'DROP ROLE IF EXISTS orthea_admin' -c 'DROP ROLE IF EXISTS consult_app' -c 'CREATE DATABASE ib'" 2>/dev/null || {
  # roles may still be owned by objects in the dolphin test db: drop that db first
  su postgres -c "$P -U postgres -c 'DROP DATABASE IF EXISTS t' -c 'DROP DATABASE IF EXISTS ib' -c 'DROP ROLE IF EXISTS orthea_admin' -c 'DROP ROLE IF EXISTS consult_app' -c 'CREATE DATABASE ib'"; }
su postgres -c "$P -U postgres -d ib -f '$D/../../consult/dolphin-launch/tests/stub_schema.sql'" >/dev/null
su postgres -c "$P -U postgres -d ib -c 'GRANT CREATE ON DATABASE ib TO orthea_admin'"
su postgres -c "$P -U orthea_admin -d ib -f '$D/../01_inbox.sql'" >/dev/null
su postgres -c "$P -U orthea_admin -d ib -f '$D/../01_inbox.sql'" >/dev/null 2>&1   # re-run is safe
su postgres -c "$B/psql -X -h /tmp/pgt -p 5499 -U postgres -d ib -f '$D/test.sql'"
