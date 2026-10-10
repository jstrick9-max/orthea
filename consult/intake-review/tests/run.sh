#!/bin/bash
# Runs the intake/review queries against a throwaway Postgres 16 (/tmp/pgt, port 5499).
set -e
D="$(cd "$(dirname "$0")" && pwd)"; Q="$D/.."
P="/usr/lib/postgresql/16/bin/psql -X -q -At -v ON_ERROR_STOP=1 -h /tmp/pgt -p 5499 -U postgres"
su postgres -c "$P -c 'DROP DATABASE IF EXISTS ir' -c 'CREATE DATABASE ir'"
su postgres -c "$P -d ir -f '$D/schema.sql'"
run() { python3 -I "$D/q.py" "$Q/$1" "$2" > /tmp/pgt/q.sql; chmod 644 /tmp/pgt/q.sql; su postgres -c "$P -d ir -f /tmp/pgt/q.sql"; }
cols() { python3 -I "$D/q.py" "$Q/$1" "$2" | sed -e 's/;[[:space:]]*$//' > /tmp/pgt/q0.sql; { echo "SELECT $3 FROM ("; cat /tmp/pgt/q0.sql; echo ") z;"; } > /tmp/pgt/q.sql; chmod 644 /tmp/pgt/q.sql; su postgres -c "$P -d ir -f /tmp/pgt/q.sql"; }
sqlq() { su postgres -c "$P -d ir -c \"$1\""; }
fail=0; check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi; }

# Single patient: parent warning + Dolphin flag
check "no parent at all → parent_name_missing" "$(cols 'C · Single patient.sql' '{"rowId":"1","email":"lso@x.com"}' "parent_name_missing||'|'||from_dolphin")" "true|yes"
check "one parent → no warning; hand-made → not from Dolphin" "$(cols 'C · Single patient.sql' '{"rowId":"2","email":"lso@x.com"}' "parent_name_missing||'|'||from_dolphin")" "false|no"
check "other practice can't read" "$(run 'C · Single patient.sql' '{"rowId":"1","email":"other@x.com"}')" ""

# Create consult: refuses empty input, accepts either field
check "create refused with no transcript/notes" "$(run 'C · Create consult.sql' '{"patientId":"1","doctorId":"60758cb2-92c4-4e2b-8c0f-9600518d7227","email":"lso@x.com","transcript":"  ","tmtNotes":""}')" ""
check "create with TMT notes only" "$(run 'C · Create consult.sql' '{"patientId":"1","doctorId":"60758cb2-92c4-4e2b-8c0f-9600518d7227","email":"lso@x.com","tmtNotes":"Class II"}')" "1"
check "create with transcript only (patient 2)" "$(run 'C · Create consult.sql' '{"patientId":"2","doctorId":"60758cb2-92c4-4e2b-8c0f-9600518d7227","email":"lso@x.com","transcript":"hello"}')" "2"

# An old empty draft (like Weave Test) for patient 1
sqlq "INSERT INTO consult.consults (practice_id,patient_id,doctor_id,consult_date,status) VALUES ('11111111-1111-1111-1111-111111111111',1,'60758cb2-92c4-4e2b-8c0f-9600518d7227',current_date,'draft')"
check "review: empty draft → needs_input=yes, from_dolphin=yes" "$(cols 'C · Consult review.sql' '{"patientId":"1","email":"lso@x.com"}' "needs_input||'|'||from_dolphin||'|'||status")" "yes|yes|draft"
check "Set generating refuses the empty draft" "$(run 'C · Set generating.sql' '{"patientId":"1","email":"lso@x.com"}')" ""
check "Save consult input: blank does nothing" "$(run 'C · Save consult input.sql' '{"patientId":"1","email":"lso@x.com","transcript":"","tmtNotes":" "}')" ""
check "Save consult input fills the draft" "$(run 'C · Save consult input.sql' '{"patientId":"1","email":"lso@x.com","transcript":"Line 1\\nLine 2","tmtNotes":""}')" "3"
check "transcript newlines restored" "$(sqlq "SELECT transcript = E'Line 1\nLine 2' FROM consult.consults WHERE id=3")" "t"
check "review: filled draft → needs_input=no" "$(cols 'C · Consult review.sql' '{"patientId":"1","email":"lso@x.com"}' "needs_input")" "no"
check "Set generating now starts it" "$(run 'C · Set generating.sql' '{"patientId":"1","email":"lso@x.com"}')" "3"
check "Save consult input refuses once not a draft" "$(run 'C · Save consult input.sql' '{"patientId":"1","email":"lso@x.com","transcript":"x"}')" ""

# Update patient contact: pick existing dentist, add new dentist, blanks keep values
check "pick existing dentist + address" "$(run 'C · Update patient contact.sql' '{"patientId":"1","email":"lso@x.com","refId":"1","refAddress":"2 New St\\nSac CA","parent1First":"Claire"}')" "1"
check "patient now has dentist 1, parent saved" "$(sqlq "SELECT referring_doctor_id||'|'||parent1_first_name FROM consult.patients WHERE id=1")" "1|Claire"
check "dentist address updated (newlines kept)" "$(sqlq "SELECT mailing_address = E'2 New St\nSac CA' FROM consult.referring_doctors WHERE id=1")" "t"
check "blank fields leave values" "$(run 'C · Update patient contact.sql' '{"patientId":"1","email":"lso@x.com"}'; sqlq "SELECT referring_doctor_id||'|'||parent1_first_name FROM consult.patients WHERE id=1")" "1
1|Claire"
run 'C · Update patient contact.sql' '{"patientId":"1","email":"lso@x.com","refId":"__new","newRefName":"Dr. Lee Chan","newRefFirst":"Lee","newRefPractice":"Chan Dental","refAddress":"9 Elm"}' >/dev/null
check "new dentist created and set" "$(sqlq "SELECT r.full_name||'|'||r.first_name||'|'||r.mailing_address FROM consult.patients p JOIN consult.referring_doctors r ON r.id=p.referring_doctor_id WHERE p.id=1")" "Dr. Lee Chan|Lee|9 Elm"
check "__new without a name creates nothing" "$(run 'C · Update patient contact.sql' '{"patientId":"1","email":"lso@x.com","refId":"__new"}' >/dev/null; sqlq "SELECT count(*) FROM consult.referring_doctors")" "3"
check "other practice's dentist id is ignored" "$(run 'C · Update patient contact.sql' '{"patientId":"1","email":"lso@x.com","refId":"2"}' >/dev/null; sqlq "SELECT referring_doctor_id FROM consult.patients WHERE id=1")" "3"
check "other practice can't edit patient" "$(run 'C · Update patient contact.sql' '{"patientId":"1","email":"other@x.com","parent1First":"Hack"}')" ""
[ $fail = 0 ] && echo ALL PASSED
