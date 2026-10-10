# Consult — Dolphin toolbar launch

Staff click **Orthea Consult** in Dolphin Management's Integrations pane and the browser opens
on that patient in Orthea Consult. Orthea never writes to Dolphin.

```
Dolphin button ─▶ launcher on the PC ─HTTPS─▶ n8n C04 ─▶ consult.dolphin_launch()  → one-time code
browser  …/consult#/launch/<code> ─▶ Budibase /launch ─▶ consult.redeem_launch() → /review or /intake
```

| Step | What | Status |
|---|---|---|
| 1 | Database: switch, keys, codes, launch + redeem functions | **built, tested** — `01_dolphin_launch.sql` |
| 2 | n8n C04 "Consult - Dolphin Launch" webhook | **built** — `C04_Consult_-_Dolphin_Launch.json`, test with `fake-launch.ps1` |
| 3 | Budibase `/launch/:t` screen | **steps below** — `02_redeem_repeat.sql`, `C · Redeem launch.sql` |
| 4 | Launcher (PowerShell first) + `dolphin.ini` line | after `/launch` works |
| 5 | Rollout at LSO, hide Add patient | after Dolphin's OK |

## How a click is matched (step 1)

Within the practice the key belongs to:

1. same Dolphin **GUID**
2. same Dolphin **Patient ID**, on a patient with no GUID yet (exactly one)
3. same **first + last name + birthday**, on a patient with no Dolphin link at all (exactly one)
4. otherwise a **new patient** is created

- Name and birthday follow Dolphin on every click; a blank from Dolphin never overwrites.
- Parents, address, referring dentist and fees are never touched (Letter Details owns them).
- An archived patient is un-archived when launched.
- Consults are not created here. Like the patient list, the launch goes to **Review** when the
  patient has a consult and to **Intake** when not; Intake creates the consult as today.
- Codes are 64 random characters, stored only as a hash, work **once**, expire after
  **2 minutes** (time to sign in to Budibase), and only for an active user of the same practice.
- Keys are stored only as a hash. `consult_app` can call the two functions but can't read the
  key or code tables, or make keys.

Tested on Postgres 16 against a copy of the live columns: `tests/run.sh` (19 checks).

## Step 1 — run it (Beekeeper, **Orthea – Voice (admin)**)

1. Run `01_dolphin_launch.sql`. The last three result sets should show your practices and two
   empty duplicate lists.
2. Turn the switch on for LSO (nothing changes on screen yet):
   ```sql
   UPDATE consult.practice_settings SET dolphin_linked = true
    WHERE practice_id = (SELECT id FROM public.practices WHERE name ILIKE '%Lemchen%');
   ```
   Check the name matches first with `SELECT id, name FROM public.practices;`.

## Step 2 — n8n C04 and a fake launch

C04 receives the button's details, calls `consult.dolphin_launch`, and answers with the link
the launcher will open:

```
POST https://listen.ortheasecurity.com/webhook/consult/dolphin/launch
Header  X-Orthea-Key: <practice key>
Body    {"guid":"{…}","dolphinId":"TESTER","firstName":"Test","lastName":"Patient","birthday":"07/15/1987"}
→ 200 {"url":"…/consult#/launch/<code>","outcome":"created"}     or 403 {"error":"…"}
```

Successful runs aren't saved in n8n's execution list (they carry patient names); failed runs are.

1. **Make LSO's key** (Beekeeper, admin):
   ```sql
   SELECT consult.create_launch_key(
     (SELECT id FROM public.practices WHERE name ILIKE '%Lemchen%'), 'LSO workstations');
   ```
   Copy the `olk_…` value somewhere safe (password manager). It can't be shown again; if it's
   lost, revoke it and make another.
2. **Find the Consult app address:** open the published Consult app on `/patients`, copy the
   address bar and drop everything from `#/` on.
3. **Import** `C04_Consult_-_Dolphin_Launch.json` into n8n. In **Settings**, paste that address
   into `consultUrl`. Check **Find or create patient** uses **Postgres – Consult (consult_app)**.
   Save, then **Active**.
4. **Fake launch:** open `fake-launch.ps1` in Notepad, paste the key into `$Key`, save, then in
   PowerShell run `powershell -ExecutionPolicy Bypass -File .\fake-launch.ps1`.
   Expect `Matched by: created` and a link. Run it again: `Matched by: guid`.
   The link won't open a patient yet: `/launch` is step 3.
5. Clean-up after testing: the fake patient is "Test Patient" (Dolphin ID TESTER); archive it
   from the patient list.

## Step 3 — Budibase `/launch/:t`

The link C04 returns is `…/consult#/launch/<code>`. The screen swaps the code for the patient
(`consult.redeem_launch`), sets `selectedPatientId` like the patient list does, and goes to
Review or Intake. A used or expired link shows a message instead.

### A. Database (Beekeeper, admin connection, Auto Commit)

Run `02_redeem_repeat.sql` (46 lines). It lets the same user re-open a code within 30 seconds,
because Budibase can run on-load actions twice. Nobody else can ever reuse a code.

### B. n8n C04 — link format

**Send link** node → in the response body, change `'#/launch?t='` to `'#/launch/'`. Save
(publish if asked).

### C. Budibase query

Data → **Consult DB** → **+ Create query** `C · Redeem launch`, Function **Read**.
Parameters (default blank): `code`, `email`. Paste `C · Redeem launch.sql`. Save (don't Run:
it would need a live code).

### D. Screen

1. Consult app → **+ Add screen** → **Blank screen**, route **`/launch/:t`**, same access role
   as `/review`. Don't add it to the navigation.
2. Add a **Container** `Launch Card` with:
   - **Text** `Launch Opening`: `Opening the patient from Dolphin…`
     Condition: **Hide** if `{{ [state].[launchDone] }}` equals `yes`.
   - **Text** `Launch Failed`: `This Dolphin link has expired or was already used. Click Orthea Consult in Dolphin again, or open the patient from Patients.`
     Condition: **Show** if `{{ [state].[launchDone] }}` equals `yes`.
   - **Button** `Launch Patients` text `Go to Patients`, On click → Navigate To `/patients`.
     Condition: **Show** if `{{ [state].[launchDone] }}` equals `yes`.
3. Select the **screen** (top of the component tree) → **On screen load** → add, in order:
   1. **Update State** — Set `launchDone` = (blank)
   2. **Execute Query** — `C · Redeem launch`; `code` = `{{ url.t }}`, `email` = `{{ [user].[email] }}`
   3. **Update State** — Set `launchDone` = `yes`
   4. **Continue if / Stop if** — Type **Continue if**; Value = the result of action 2 followed by
      `.0.destination` (see below); Operator **Not equals**; Reference value blank
   5. **Update State** — Set `selectedPatientId`, **Persist** on, Value = action 2's result + `.0.patient_id`
   6. **Navigate To** — Screen, URL = action 2's result + `.0.destination`

   **Action 2's result:** in the value box open the bindings drawer; under the actions section
   pick **Action 2 → Result**. It inserts a binding ending in `}}` — type `.0.destination`
   (or `.0.patient_id`) just before the `}}`.

Once 4–6 work, success never shows the screen for more than a moment: it moves straight on.

### E. Test

1. `fake-launch.ps1` → copy the link → open it in the browser where you're signed in to the
   published app. Expect Test Patient's Intake (or Review if it has a consult).
2. Open the same link again a minute later → the "expired or already used" message.
3. Open a fresh link in a **private window** (signed out): sign in, and check whether you land on
   the patient or on the home screen. Tell me which — it decides whether the sign-in step needs
   handling before rollout.
