#!/bin/sh
# Tests OrtheaLaunch.ps1 with PowerShell 7 against mock_c04.py. Usage: run.sh /path/to/pwsh
PWSH="$1"; D="$(cd "$(dirname "$0")" && pwd)"; T="$(mktemp -d)"
python3 -I "$D/mock_c04.py" 18765 "$T/requests.jsonl" & MOCK=$!; sleep 1
export ProgramData="$T" LOCALAPPDATA="$T"   # Windows folders, faked for Linux
export ORTHEA_LAUNCH_TEST=1 ORTHEA_LAUNCH_ENDPOINT=http://127.0.0.1:18765/ ORTHEA_LAUNCH_LOGFILE="$T/launch.log"
printf 'olk_good\r\n' > "$T/good.key"; printf 'olk_bad' > "$T/bad.key"
L="$D/../OrtheaLaunch.ps1"; fail=0
check() { if echo "$2" | grep -qF -- "$3"; then echo "ok   $1"; else echo "FAIL $1 -> $2"; fail=1; fi; }
run() { ORTHEA_LAUNCH_KEYFILE="$1" "$PWSH" -NoProfile -File "$L" "${@:2}" 2>&1; echo "exit=$?"; }
o=$(ORTHEA_LAUNCH_KEYFILE=$T/good.key "$PWSH" -NoProfile -File "$L" -Guid '{8DEB5881-00BC-4F30-8BCF-798E892B9602}' -DolphinId TESTER -FirstName Test -LastName Patient -Birthday 07/15/1987 2>&1; echo "exit=$?")
check "good key opens the Orthea link" "$o" "OPEN: https://orthea-budibase.eqawdd.easypanel.host/app/default%20workspace/consult#/launch/abc123"
check "good key exits 0" "$o" "exit=0"
o=$(ORTHEA_LAUNCH_KEYFILE=$T/good.key "$PWSH" -NoProfile -File "$L" -Guid '{AAAA}' -DolphinId 'OBRIEN' -FirstName "Seán & Zoë" -LastName "O'Brien-Núñez" -Birthday 01/02/2015 2>&1)
check "names with ' & accents still open" "$o" "OPEN: "
tail -1 "$T/requests.jsonl" | python3 -I -c "import json,sys; b=json.load(sys.stdin)['body']; sys.exit(0 if (b['firstName'],b['lastName'])==('Seán & Zoë',\"O'Brien-Núñez\") else 1)" && echo "ok   names arrive intact (UTF-8)" || { echo "FAIL names: $(tail -1 $T/requests.jsonl)"; fail=1; }
tail -1 "$T/requests.jsonl" | grep -qF '"key": "olk_good"' && echo "ok   key sent in header, trimmed" || { echo "FAIL key header"; fail=1; }
o=$(ORTHEA_LAUNCH_KEYFILE=$T/bad.key "$PWSH" -NoProfile -File "$L" -Guid '{X}' -DolphinId X -FirstName A -LastName B 2>&1; echo "exit=$?")
check "refused key -> admin message" "$o" "did not accept this computer's key"
check "refused key exits 1, opens nothing" "$o" "exit=1"
o=$(ORTHEA_LAUNCH_KEYFILE=$T/good.key "$PWSH" -NoProfile -File "$L" -Guid '=' -DolphinId '=' -FirstName '=' -LastName '=' -Birthday '=' 2>&1)
check "no patient -> message, nothing sent" "$o" "Dolphin did not send a patient"
o=$(ORTHEA_LAUNCH_KEYFILE=$T/missing.key "$PWSH" -NoProfile -File "$L" -Guid '{X}' -DolphinId X 2>&1)
check "no key file -> setup message" "$o" "not set up on this computer"
o=$(ORTHEA_LAUNCH_KEYFILE=$T/good.key "$PWSH" -NoProfile -File "$L" -Guid '{X}' -DolphinId ERR500 -FirstName A -LastName B 2>&1)
check "server error -> try again message" "$o" "(error 500)"
o=$(ORTHEA_LAUNCH_KEYFILE=$T/good.key "$PWSH" -NoProfile -File "$L" -Guid '{X}' -DolphinId EVIL -FirstName A -LastName B 2>&1)
check "link to another site is not opened" "$o" "unexpected reply"
echo "$o" | grep -q "OPEN:" && { echo "FAIL evil link opened"; fail=1; }
o=$(ORTHEA_LAUNCH_KEYFILE=$T/good.key "$PWSH" -NoProfile -File "$L" -Guid '={8DEB}' -DolphinId '=TESTER' -FirstName '=Test' -LastName '=Patient' -Birthday '=' 2>&1)
check "= prefix stripped, blank birthday OK" "$o" "OPEN: "
tail -1 "$T/requests.jsonl" | python3 -I -c "import json,sys; b=json.load(sys.stdin)['body']; sys.exit(0 if (b['guid'],b['dolphinId'],b['birthday'])==('{8DEB}','TESTER','') else 1)" && echo "ok   values arrive without the = prefix" || { echo "FAIL prefix: $(tail -1 $T/requests.jsonl)"; fail=1; }
o=$(ORTHEA_LAUNCH_KEYFILE=$T/good.key "$PWSH" -NoProfile -File "$L" -Guid '{X}' -DolphinId TEXT -FirstName A -LastName B 2>&1)
check "reply sent as plain text still opens" "$o" "OPEN: https://orthea-budibase.eqawdd.easypanel.host/app/x/consult#/launch/t1"
kill $MOCK; sleep 0.5
o=$(ORTHEA_LAUNCH_KEYFILE=$T/good.key "$PWSH" -NoProfile -File "$L" -Guid '{X}' -DolphinId X -FirstName A -LastName B 2>&1)
check "Orthea unreachable -> connection message" "$o" "Could not reach Orthea"
if [ ! -s "$T/launch.log" ]; then echo "FAIL no log written"; fail=1; elif grep -qE "Test Patient|TESTER|OBRIEN|O'Brien|Zoë|8DEB5881|olk_|launch/" "$T/launch.log"; then echo "FAIL log contains patient data, key or link"; cat "$T/launch.log"; fail=1; else echo "ok   log has no names, IDs, key or link ($(wc -l < $T/launch.log) lines)"; fi
rm -rf "$T"; [ $fail = 0 ] && echo ALL PASSED
