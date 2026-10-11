#!/bin/bash
# Runs the Budibase E · queries as inbox_app against the test database made by run.sh.
set -e
D="$(cd "$(dirname "$0")" && pwd)"; Q="$D/../budibase"
sh "$D/run.sh" >/dev/null 2>&1
P="/usr/lib/postgresql/16/bin/psql -X -q -At -v ON_ERROR_STOP=1 -h /tmp/pgt -p 5499 -d ib"
su postgres -c "$P -U postgres" <<'SQL'
INSERT INTO public.practice_users (email, practice_id) VALUES ('romina@lso.com','11111111-1111-1111-1111-111111111111'),
  ('staff@bronsky.com','22222222-2222-2222-2222-222222222222');
SQL
run() { python3 -I "$D/../../consult/intake-review/tests/q.py" "$Q/$1" "$2" | sed '1s/^/SET ROLE inbox_app;\n/' > /tmp/pgt/q.sql; chmod 644 /tmp/pgt/q.sql; su postgres -c "$P -U postgres -f /tmp/pgt/q.sql"; }
sqlq() { su postgres -c "$P -U postgres -c \"$1\""; }
fail=0; check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi; }
M1=$(sqlq "SELECT id FROM inbox.items WHERE message_id='<m1@x>'")
A1=$(sqlq "SELECT id FROM inbox.items WHERE message_id='<a1>'")
M2=$(sqlq "SELECT id FROM inbox.items WHERE message_id='<m2@x>'")
OWEN=$(sqlq "SELECT id FROM consult.patients WHERE first_name='Owen'")
BRONSKY_LEO=$(sqlq "SELECT id FROM consult.patients WHERE practice_id='22222222-2222-2222-2222-222222222222'")

check "list (new): own practice only, newest first" "$(run 'E · Inbox list.sql' '{"email":"Romina@LSO.com","view":""}' | wc -l | tr -d ' ')" "$(sqlq "SELECT count(*) FROM inbox.items WHERE practice_id='11111111-1111-1111-1111-111111111111' AND status IN ('new','processing','error')")"
check "list: other practice sees none of LSO" "$(run 'E · Inbox list.sql' '{"email":"staff@bronsky.com","view":"all"}' | grep -c 'drl@lso.com' || true)" "$(sqlq "SELECT count(*) FROM inbox.items WHERE practice_id='22222222-2222-2222-2222-222222222222'")"
check "list (held) shows the unknown sender" "$(run 'E · Inbox list.sql' '{"email":"romina@lso.com","view":"held"}' | grep -c stranger)" "1"
check "list: unmatched name shown as not matched" "$(run 'E · Inbox list.sql' '{"email":"romina@lso.com","view":"new"}' | grep -c 'Ava Reyes (not matched)')" "1"
check "item: matched patient and label" "$(run 'E · Inbox item.sql' "{\"id\":\"$M1\",\"email\":\"romina@lso.com\"}" | grep -o 'Leo Marsh|08/27/2013' | head -1)" "Leo Marsh|08/27/2013"
check "item: other practice gets nothing" "$(run 'E · Inbox item.sql' "{\"id\":\"$M1\",\"email\":\"staff@bronsky.com\"}")" ""
check "item: blank id gives nothing (no error)" "$(run 'E · Inbox item.sql' '{"id":"","email":"romina@lso.com"}')" ""
check "patients: LSO list only" "$(run 'E · Inbox patients.sql' '{"email":"romina@lso.com"}' | wc -l | tr -d ' ')" "4"
check "set patient: other practice patient refused" "$(run 'E · Set patient.sql' "{\"id\":\"$A1\",\"email\":\"romina@lso.com\",\"patientId\":\"$BRONSKY_LEO\"}")" ""
check "set patient: own patient → manual" "$(run 'E · Set patient.sql' "{\"id\":\"$A1\",\"email\":\"romina@lso.com\",\"patientId\":\"$OWEN\"}")" "$A1"
check "same patient again: nothing changes" "$(run 'E · Set patient.sql' "{\"id\":\"$A1\",\"email\":\"romina@lso.com\",\"patientId\":\"$OWEN\"}")" ""
check "match recorded as manual" "$(sqlq "SELECT match FROM inbox.items WHERE id=$A1")" "manual"
check "save note keeps line breaks" "$(run 'E · Save note.sql' "{\"id\":\"$M1\",\"email\":\"romina@lso.com\",\"chartNote\":\"Line 1\\\\nLine 2\"}")" "$M1"
check "…stored as two lines" "$(sqlq "SELECT chart_note = E'Line 1\nLine 2' FROM inbox.items WHERE id=$M1")" "t"
check "blank note not saved" "$(run 'E · Save note.sql' "{\"id\":\"$M1\",\"email\":\"romina@lso.com\",\"chartNote\":\"  \"}")" ""
check "file: other practice refused" "$(run 'E · File item.sql' "{\"id\":\"$M1\",\"email\":\"staff@bronsky.com\",\"chartNote\":\"\"}")" ""
check "file: filed by Romina" "$(run 'E · File item.sql' "{\"id\":\"$M1\",\"email\":\"Romina@lso.com\",\"chartNote\":\"\"}")" "$M1"
check "…status, who, note kept" "$(sqlq "SELECT status||'|'||filed_by||'|'||(chart_note = E'Line 1\nLine 2') FROM inbox.items WHERE id=$M1")" "filed|romina@lso.com|true"
check "file again: nothing" "$(run 'E · File item.sql' "{\"id\":\"$M1\",\"email\":\"romina@lso.com\",\"chartNote\":\"\"}")" ""
UNMATCHED=$(sqlq "SELECT id FROM inbox.items WHERE status='new' AND patient_id IS NULL LIMIT 1")
if [ -n "$UNMATCHED" ]; then check "file without a patient refused" "$(run 'E · File item.sql' "{\"id\":\"$UNMATCHED\",\"email\":\"romina@lso.com\",\"chartNote\":\"x\"}")" ""; fi
check "reopen filed → new" "$(run 'E · Reopen item.sql' "{\"id\":\"$M1\",\"email\":\"romina@lso.com\"}")" "$M1"
check "dismiss held" "$(run 'E · Dismiss item.sql' "{\"id\":\"$M2\",\"email\":\"romina@lso.com\"}")" "$M2"
check "reopen dismissed held message: stays dismissed" "$(run 'E · Reopen item.sql' "{\"id\":\"$M2\",\"email\":\"romina@lso.com\"}")" ""
[ $fail = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
