# Orthea Consult — Dolphin launcher (step 4)

A small PowerShell script that sits on each LSO workstation. Dolphin runs it when staff click
**Orthea Consult** in the Integrations pane; it asks Orthea for a one-time link and opens it.

| File | Goes to | Purpose |
|---|---|---|
| `OrtheaLaunch.ps1` | `C:\Program Files\Orthea\` | the launcher (about 120 lines, plain text, readable) |
| `orthea.bmp` | `C:\Program Files\Orthea\` | 24×24 toolbar icon |
| practice key | `C:\ProgramData\Orthea\launch.key` | written by the installer; staff can read, only admins can change |
| `Install-OrtheaLaunch.ps1` | run once per PC, as admin | copies the two files, asks for the key, prints the `dolphin.ini` line |
| `Uninstall-OrtheaLaunch.ps1` | run as admin | removes both folders |

## What happens on a click

1. Dolphin fills in each value after a `=` (so a blank value is still passed; the launcher strips it):
   `{PatientGUID} {PatientID} {PatientFirstName} {PatientLastName} {PatientBirthday}`
   and starts Windows PowerShell (built into Windows) with the launcher. If no patient is open,
   Dolphin shows its own patient chooser first.
2. The launcher checks it got a GUID or ID, reads the key file, and sends the five values plus the
   key to `https://listen.ortheasecurity.com/webhook/consult/dolphin/launch` (HTTPS, TLS 1.2,
   20-second limit).
3. It opens the reply in the default browser **only if** it is an Orthea Consult `#/launch/` link
   on `orthea-budibase.eqawdd.easypanel.host`. Anything else is refused.
4. If anything fails, staff see one short message box (no technical detail), e.g. "Could not reach
   Orthea… or open the patient from Orthea's patient list."

## What it never does

- Never writes to Dolphin, its database, its folders, `dolphin.ini` or the registry.
- Never puts names or birthdays in a web address (only the one-time code goes in the link).
- Never logs patient data: `%LOCALAPPDATA%\Orthea\launch.log` holds date, time and result only
  (e.g. `2026-10-10 14:23:44  opened (guid)`).
- Needs no admin rights to run, installs no service, nothing runs in the background.

## The key

Staff accounts can read `launch.key` (the launcher runs as them). The key alone cannot read any
patient data: it can only add or refresh a patient's name/birthday in LSO's Orthea and get a link
that only a signed-in LSO user can open. It can be revoked any time
(`UPDATE consult.launch_keys SET revoked_at = now() WHERE id = …;`) and a new one installed.

## Tested (`tests/run.sh`, PowerShell 7 against a stand-in for C04)

Good key opens the link · names with `'`, `&` and accents arrive intact · refused key, missing
key file, no patient, server error and unreachable Orthea each show the right message and open
nothing · a reply pointing at another site is refused · a plain-text reply still works · the log
contains no names, IDs, key or link. Windows PowerShell 5.1 rehearsal on a Windows 11 PC passed
(2026-10-10): install, launch, blank birthday, no-patient message, log.

## Testing at LSO — careful order

**0. Rehearse on your own PC (no Dolphin needed).**
Run the installer, then run the launcher by hand the way Dolphin would:
```
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Orthea\OrtheaLaunch.ps1" -Guid "={8DEB5881-00BC-4F30-8BCF-798E892B9602}" -DolphinId "=TESTER" -FirstName "=Test" -LastName "=Patient" -Birthday "=07/15/1987"
```
Expect Test Patient to open. Then run the uninstaller, so you've practised the undo too.

**1. Before touching LSO.**
- Dolphin's written answer on third-party toolbar buttons, or LSO's informed go-ahead to test.
- Agree a time with LSO (lunch or after hours) and tell the office manager what will change.
- Find out **where `dolphin.ini` lives**. If it's on the server and shared, one line adds the
  button to *every* workstation at once — then test on a PC that can use its own copy, or plan
  the test for when nobody else is in Dolphin.
- On the test PC, check `Get-ExecutionPolicy -List` (PowerShell). If `MachinePolicy` says
  `AllSigned` or `RemoteSigned`, LSO's IT blocks unsigned scripts and we need a signed version first.

**2. One workstation, test patient only.**
1. Close Dolphin. Copy `dolphin.ini` to `dolphin.ini.before-orthea-YYYY-MM-DD`.
2. Run the installer (admin), paste the key, add the printed line under `[Toolbar]`.
3. Open Dolphin. Check the existing buttons (Models, Invisalign, EasyRx, …) are all still there.
4. Open **TESTER**, click **Orthea Consult** → Test Patient opens in the browser.
5. With no patient open, click it → Dolphin's chooser → pick TESTER → opens.
6. Note: a black PowerShell window may flash for a moment. That's expected with a script; a
   signed .exe later removes it.

**3. Undo, rehearsed.** Close Dolphin, restore the `.before-orthea` copy, run the uninstaller.
Under two minutes; Dolphin is exactly as before.

**4. Real patients**, one staff member, one workstation, for a week before any other PC.
