#!/bin/sh
# Throwaway Postgres 16 on /tmp/pgt port 5499 (see consult/downloads/tools for setup).
set -e
B=/usr/lib/postgresql/16/bin; D="$(cd "$(dirname "$0")" && pwd)"
P="$B/psql -X -q -v ON_ERROR_STOP=1 -h /tmp/pgt -p 5499"
su postgres -c "$P -U postgres -c 'DROP DATABASE IF EXISTS t' -c 'DROP ROLE IF EXISTS orthea_admin' -c 'DROP ROLE IF EXISTS consult_app' -c 'CREATE DATABASE t'"
su postgres -c "$P -U postgres -d t -f '$D/stub_schema.sql'"
su postgres -c "$P -U orthea_admin -d t -f '$D/../01_dolphin_launch.sql'" >/dev/null
su postgres -c "$P -U orthea_admin -d t -f '$D/../01_dolphin_launch.sql'" >/dev/null 2>&1   # re-run is safe
su postgres -c "$P -U orthea_admin -d t -f '$D/../02_redeem_repeat.sql'" >/dev/null
su postgres -c "$P -U orthea_admin -d t -f '$D/../03_dolphin_open.sql'" >/dev/null
su postgres -c "$P -U orthea_admin -d t -f '$D/../03_dolphin_open.sql'" >/dev/null 2>&1   # re-run is safe
su postgres -c "$B/psql -X -h /tmp/pgt -p 5499 -U postgres -d t -f '$D/test.sql'"
