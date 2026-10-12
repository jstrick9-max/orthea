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
M2=$(sqlq "SELECT id FROM inbox.items WHERE message_id='<m2@x>'")

sqlq "INSERT INTO inbox.items (practice_id, message_id, to_address, from_email, status, patient_first, patient_last) VALUES ('11111111-1111-1111-1111-111111111111','<ava>','lso.inbox@ortheasecurity.com','drl@lso.com','new','Ava','Reyes')"
check "list (new): own practice only" "$(run 'E · Inbox list.sql' '{"email":"Romina@LSO.com","view":""}' | wc -l | tr -d ' ')" "$(sqlq "SELECT count(*) FROM inbox.items WHERE practice_id='11111111-1111-1111-1111-111111111111' AND status IN ('new','processing','error')")"
check "list: other practice sees only its own inbox" "$(run 'E · Inbox list.sql' '{"email":"staff@bronsky.com","view":"all"}' | wc -l | tr -d ' ')" "$(sqlq "SELECT count(*) FROM inbox.items WHERE practice_id='22222222-2222-2222-2222-222222222222'")"
check "list (held) shows the unknown sender" "$(run 'E · Inbox list.sql' '{"email":"romina@lso.com","view":"held"}' | grep -c stranger)" "1"
check "list: patient = name as confirmed" "$(run 'E · Inbox list.sql' '{"email":"romina@lso.com","view":"new"}' | grep -c '|Ava Reyes|')" "1"
check "list: sender name from the approved list" "$(run 'E · Inbox list.sql' '{"email":"romina@lso.com","view":"new"}' | grep -c '|Dr. Lemchen|')" "$(sqlq "SELECT count(*) FROM inbox.items WHERE from_email='drl@lso.com' AND status IN ('new','processing','error')")"
check "item: patient fields" "$(run 'E · Inbox item.sql' "{\"id\":\"$M1\",\"email\":\"romina@lso.com\"}" | grep -o 'leo|MARSH|08/27/2013' | head -1)" "leo|MARSH|08/27/2013"
check "item: other practice gets nothing" "$(run 'E · Inbox item.sql' "{\"id\":\"$M1\",\"email\":\"staff@bronsky.com\"}")" ""
check "item: blank id gives nothing (no error)" "$(run 'E · Inbox item.sql' '{"id":"","email":"romina@lso.com"}')" ""
check "set patient: name + MM/DD/YYYY" "$(run 'E · Set patient.sql' "{\"id\":\"$M1\",\"email\":\"romina@lso.com\",\"firstName\":\" Leo \",\"lastName\":\"Marsh\",\"dob\":\"8/27/2013\"}")" "$M1"
check "…stored tidy" "$(sqlq "SELECT patient_first||'|'||patient_last||'|'||patient_dob FROM inbox.items WHERE id=$M1")" "Leo|Marsh|2013-08-27"
check "set patient: ISO date accepted" "$(run 'E · Set patient.sql' "{\"id\":\"$M1\",\"email\":\"romina@lso.com\",\"firstName\":\"Leo\",\"lastName\":\"Marsh\",\"dob\":\"2013-08-27T00:00:00.000Z\"}")" "$M1"
check "set patient: other practice refused" "$(run 'E · Set patient.sql' "{\"id\":\"$M1\",\"email\":\"staff@bronsky.com\",\"firstName\":\"X\",\"lastName\":\"Y\",\"dob\":\"\"}")" ""
check "save note keeps line breaks" "$(run 'E · Save note.sql' "{\"id\":\"$M1\",\"email\":\"romina@lso.com\",\"chartNote\":\"Line 1\\\\nLine 2\"}")" "$M1"
check "…stored as two lines" "$(sqlq "SELECT chart_note = E'Line 1\nLine 2' FROM inbox.items WHERE id=$M1")" "t"
check "blank note not saved" "$(run 'E · Save note.sql' "{\"id\":\"$M1\",\"email\":\"romina@lso.com\",\"chartNote\":\"  \"}")" ""
M5=$(sqlq "SELECT id FROM inbox.items WHERE message_id='<m5@x>'")
check "file without a patient name refused" "$(run 'E · File item.sql' "{\"id\":\"$M5\",\"email\":\"romina@lso.com\",\"chartNote\":\"x\"}")" ""
check "file: other practice refused" "$(run 'E · File item.sql' "{\"id\":\"$M1\",\"email\":\"staff@bronsky.com\",\"chartNote\":\"\"}")" ""
check "file: filed by Romina" "$(run 'E · File item.sql' "{\"id\":\"$M1\",\"email\":\"Romina@lso.com\",\"chartNote\":\"\"}")" "$M1"
check "…status, who, note kept" "$(sqlq "SELECT status||'|'||filed_by||'|'||(chart_note = E'Line 1\nLine 2') FROM inbox.items WHERE id=$M1")" "filed|romina@lso.com|true"
check "set patient on a filed message: nothing" "$(run 'E · Set patient.sql' "{\"id\":\"$M1\",\"email\":\"romina@lso.com\",\"firstName\":\"Z\",\"lastName\":\"Z\",\"dob\":\"\"}")" ""
check "reopen filed → new" "$(run 'E · Reopen item.sql' "{\"id\":\"$M1\",\"email\":\"romina@lso.com\"}")" "$M1"
check "dismiss held" "$(run 'E · Dismiss item.sql' "{\"id\":\"$M2\",\"email\":\"romina@lso.com\"}")" "$M2"
check "reopen dismissed held message: stays dismissed" "$(run 'E · Reopen item.sql' "{\"id\":\"$M2\",\"email\":\"romina@lso.com\"}")" ""
[ $fail = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
