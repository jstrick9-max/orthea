# Consult — Dolphin toolbar launch

Staff click **Orthea Consult** in Dolphin Management's Integrations pane and the browser opens
on that patient in Orthea Consult. Orthea never writes to Dolphin.

```
Dolphin button ─▶ launcher on the PC ─HTTPS─▶ n8n C04 ─▶ consult.dolphin_launch()  → one-time code
browser  …/consult#/launch?t=<code> ─▶ Budibase /launch ─▶ consult.redeem_launch() → /review or /intake
```

| Step | What | Status |
|---|---|---|
| 1 | Database: switch, keys, codes, launch + redeem functions | **built, tested** — `01_dolphin_launch.sql` |
| 2 | n8n C04 "Consult - Dolphin Launch" webhook | next |
| 3 | Budibase `/launch` screen | after C04 |
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

The practice key is made in step 2, when C04 is ready to test.
