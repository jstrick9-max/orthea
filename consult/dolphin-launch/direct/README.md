# Dolphin button — direct version (nothing installed on the PCs)

The button opens Chrome straight at Orthea Consult with the patient's details **after the `#`**,
the same way LSO's EasyRx button works, except EasyRx puts them before the `#` (sent to its
servers). After the `#` they stay in the browser: never sent to a server or logged, but kept in that
PC's browser history.

```
Dolphin button ─▶ chrome.exe "…/consult#/dolphin?g={PatientGUID}&i={PatientID}&f=…&l=…&b=…"
Budibase /dolphin ─▶ consult.dolphin_open(signed-in email, values) ─▶ /review or /intake
```

No key, no n8n: the practice comes from the signed-in Budibase user, who must be active in a
practice with Consult and the Dolphin link on. Matching is the same as the launcher path
(GUID → Dolphin ID → name + birthday → new patient). The launcher (`../launcher/`) and C04 stay
built for later.

Tested on Postgres 16 (`../tests/run.sh`, 34 checks, incl. 9 for this path).

Known limits: a first or last name containing `&`, `#` or `+` arrives cut short or changed
(EasyRx has the same limit). Very rare; staff can correct the name in Orthea, and the next click
won't overwrite it with a blank.

## 1. Database (Beekeeper, admin connection, Auto Commit)

Run `../03_dolphin_open.sql`. Before **Run All**, scroll to the bottom: the last line must be
`-- END OF 03_dolphin_open.sql`. The final result should list `dolphin_launch`, `dolphin_match`,
`dolphin_open`.

## 2. Budibase query

Data → **Consult DB** → **+ Create query** `C · Dolphin open`, Function **Read**. Parameters, all
default blank: `email`, `guid`, `dolphinId`, `firstName`, `lastName`, `birthday`. Paste
`C · Dolphin open.sql`. Save (don't Run).

## 3. Screen `/dolphin` (copy of `/launch/:t`)

1. In the Screens list, hover **`/launch/:t`** → **⋯ → Duplicate**. On the copy set Route to
   **`/dolphin`** (no `:t`). Keep it out of Navigation.
2. Change **Launch Failed** text to:
   `Orthea couldn't open this patient from Dolphin: {{ [state].[launchReason] }}. Open the patient from Patients instead.`
3. **On screen load** — change only these:
   - **Action 2 (Execute Query)** → query **`C · Dolphin open`**, tick **Do not display default
     notification**. Bindings: `email` = `{{ [user].[email] }}`; the other five each use
     **JavaScript B** with its letter: `guid` → `g`, `dolphinId` → `i`, `firstName` → `f`,
     `lastName` → `l`, `birthday` → `b`.
   - **Add** an **Update State** right after action 2: Set `launchReason`, Value = JavaScript A with
     `reason` (see below). Drag it to position 3.
   - Actions *Continue if*, *Update State selectedPatientId*, *Navigate To* stay as they are
     (JavaScript A reads `Action 2.Query result` — still the right action).

**JavaScript A** (already on the copied actions):
```js
const r = $("Action 2.Query result");
const rows = Array.isArray(r) ? r : ((r && (r.data || r.rows)) || []);
return (rows[0] && rows[0].destination) || "";   // patient_id / reason for the others
```

**JavaScript B** — reads one value from the address (change `"g"` to the letter):
```js
const h = window.location.hash || "";
const i = h.indexOf("?");
return new URLSearchParams(i >= 0 ? h.slice(i + 1) : "").get("g") || "";
```

Publish.

## 4. Rehearse on your own PC (no Dolphin)

Paste this into Chrome's address bar (signed in to the published app):
```
https://orthea-budibase.eqawdd.easypanel.host/app/default%20workspace/consult#/dolphin?g={8DEB5881-00BC-4F30-8BCF-798E892B9602}&i=TESTER&f=Test&l=Patient&b=07/15/1987
```
Expect Test Patient's Intake. Also try `b=` empty, and a made-up patient (new GUID and ID) to see a
new patient created — archive it afterwards.

## 5. The `dolphin.ini` line (one workstation at LSO)

Add under `[Toolbar]`, after the `itero=` line, as **one line**:
```
OrtheaConsult=Orthea Consult,Open this patient in Orthea Consult,C:\Dolphin\Buttons\orthea.bmp,C:\Program Files\Google\Chrome\Application\chrome.exe "https://orthea-budibase.eqawdd.easypanel.host/app/default%20workspace/consult#/dolphin?g={PatientGUID}&i={PatientID}&f={PatientFirstName}&l={PatientLastName}&b={PatientBirthday}"
```
- Same Chrome path as the EasyRx line on that PC (check it matches on each workstation).
- `orthea.bmp` doesn't exist there, so the icon is blank; the button still works. (Copying
  `../launcher/orthea.bmp` into `C:\Dolphin\Buttons\` later gives it an icon.)
- Exactly three commas before `C:\Program Files\Google…`; none inside the address.

At LSO:
1. Close Dolphin. Copy `Dolphin.ini` → `Dolphin.ini.before-orthea-YYYY-MM-DD` (same folder).
2. Open `Dolphin.ini` in Notepad, paste the line, **Save** (don't change the encoding).
3. Open Dolphin → Integrations: the other six buttons are all there, plus **Orthea Consult**.
4. Open **TESTER** → click **Orthea Consult** → Test Patient opens in Chrome.
5. No patient open → click → Dolphin's chooser → TESTER → opens.
6. **Undo** (rehearse it once): close Dolphin, delete `Dolphin.ini`, rename the backup back.
