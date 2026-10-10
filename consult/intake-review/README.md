# Consult — Intake & Review fixes for Dolphin patients (2026-10-10)

| # | Fix | Where |
|---|---|---|
| 1 | A consult can't be saved with neither transcript nor TMT notes | Intake button + `C · Create consult` |
| 2 | A draft saved without input can get it on Review → **Save & generate letters** | Review + new `C · Save consult input`; `C · Set generating` refuses empty consults |
| 3 | Referring dentist picker on Intake (incl. **+ Add new referring doctor**, which really creates one) | Intake + `C · Update patient contact` |
| 4 | Parent warning only when **no** parent name is on file; Parent 2 optional | `C · Single patient` + Intake text |
| 5 | Consult date shows today | Intake |
| 6 | **Regenerate all** hidden while there's nothing to generate from | Review |
| 7 | **Add patient** for admins only (Dolphin creates patients) | Navigation, `/newpatient`, Patients button |
| 8 | **Linked to Dolphin** tag | Intake + Review |

Tested on Postgres 16 against a copy of the live columns: `tests/run.sh` (23 checks).

Component ids below are from the 2026-10-10 export: Consult Form `cac6e2b2bfca94b4f861296cab8fb7c4f`,
Patient provider (Intake) `c16bd02cddafd49a89e62020ebc979786`, Consult Review provider
`cf63413f4229447ef864d862c5627ee22`.

---

## Step 1 — Queries (Data → Consult DB)

1. **`C · Single patient`** — replace the SQL. Save, then **Run** once (new column `from_dolphin`).
2. **`C · Consult review`** — replace the SQL. Run, Save (new columns `needs_input`, `from_dolphin`).
3. **`C · Create consult`** — replace the SQL. Save.
4. **`C · Set generating`** — replace the SQL. Save.
5. **`C · Update patient contact`** — first add 5 parameters (Default blank): `refId`, `newRefName`,
   `newRefFirst`, `newRefPractice`, `newRefEmail`. Then replace the SQL. Save.
6. **+ Create query `C · Save consult input`**, Function **Update**, parameters (Default blank):
   `patientId`, `email`, `transcript`, `tmtNotes`. Paste the SQL. Save.

Check the default values of every query you touched are blank (except where they were before).

## Step 2 — Intake (`/intake/:id`)

**Patient card**
- **Parent Warning** → text: `⚠ No parent name yet. The family letter needs at least one parent's first name.`
  (keep its condition).
- Add **Text** `Dolphin Tag` right under **Patient Name**: text `Linked to Dolphin`.
  Condition: **Show** if `{{ [c16bd02cddafd49a89e62020ebc979786].[rows].0.from_dolphin }}` equals `yes`.

**Referring dentist** (Family card)
- Add a **Data Provider** `Ref Doctors` next to the existing `Doctors` provider (top of the screen):
  Datasource `C · Referring doctors`, `email` = `{{ [user].[email] }}`.
- In **Family Card Body**, above **Referring Address**, add an **Options Picker** `Referrer Picker`:
  Field `refId`, Label `Referring dentist`, Options source **Data provider** → `Ref Doctors`,
  Label column `full_name`, Value column `id`,
  Default value `{{ [c16bd02cddafd49a89e62020ebc979786].[rows].0.referring_doctor_id }}`.
- Below it, four **Text fields**, each with Condition **Show** if
  `{{ [cac6e2b2bfca94b4f861296cab8fb7c4f].[refId] }}` equals `__new`:

  | Name | Field | Label |
  |---|---|---|
  | `New Ref Name` | `newRefName` | `New dentist: full name` (placeholder `Dr. Kim Park`) |
  | `New Ref First` | `newRefFirst` | `First name (for the "Hi …," greeting)` |
  | `New Ref Practice` | `newRefPractice` | `Practice name` |
  | `New Ref Email` | `newRefEmail` | `Email` |
- **Referring Address** → Label `Dentist mailing address`.

**Consult date** — **Consult Date** → Default value → ⚡ JavaScript:
```js
const d = new Date();
return new Date(d.getFullYear(), d.getMonth(), d.getDate()).toISOString();
```

**Save Consult Button**
- Action 2 (**Execute Query `C · Update patient contact`**) — set the 5 new bindings:
  `refId` = `{{ [cac6e2b2bfca94b4f861296cab8fb7c4f].[refId] }}`, and likewise `newRefName`,
  `newRefFirst`, `newRefPractice`, `newRefEmail` (same form, field of the same name).
- Conditions → **Update setting** `Disabled` = true, if
  `{{ [cac6e2b2bfca94b4f861296cab8fb7c4f].[transcript] }}{{ [cac6e2b2bfca94b4f861296cab8fb7c4f].[tmtNotes] }}`
  equals (blank reference value).
- In **Footer Row**, add **Text** `Save Hint`: `Add a transcript or TMT notes to save the consult.`
  Condition **Show** with the same binding equals (blank).

## Step 3 — Review (`/review/:id`)

- In **Header Identity**, under **Status Pill**, add **Text** `Dolphin Tag`: `Linked to Dolphin`.
  Condition **Show** if `{{ [cf63413f4229447ef864d862c5627ee22].[rows].0.from_dolphin }}` equals `yes`.
- **Generate Button** → add Condition **Hide** if
  `{{ [cf63413f4229447ef864d862c5627ee22].[rows].0.needs_input }}` equals `yes`.

**Add the missing input** (inside **Inputs Card Body**, at the top):
1. Add a **Container** `Input Needed`. Condition **Show** if `…needs_input` (as above) equals `yes`.
2. Inside it: **Text** `Input Needed Note`:
   `This consult was saved without a transcript or TMT notes. Add at least one to generate the letters.`
3. Inside it: a **Form** `Input Form` (Custom), containing two **Long Form fields**:
   `Input Transcript` (field `transcript`, label `Transcript or Plaud note`) and
   `Input Notes` (field `tmtNotes`, label `TMT notes (optional)`).
4. **Duplicate** the **Generate Button** (it carries the wait-for-letters actions) and drag the copy into
   `Input Form`. Rename it `Save Input`, text `Save & generate letters`. On the copy:
   - Conditions: delete the copied ones. Add **Update setting** `Disabled` = true if
     `{{ [Input Form].[transcript] }}{{ [Input Form].[tmtNotes] }}` equals (blank) — pick the form
     fields from the ⚡ drawer.
   - On click: **Add Action → Execute Query `C · Save consult input`**: `patientId` =
     `{{ [state].[selectedPatientId] }}`, `email` = `{{ [user].[email] }}`, `transcript` / `tmtNotes` =
     the two `Input Form` fields. Drag it to **position 1**.
   - Action 2 (`C · Set generating`, the copied first action): untick **Require confirmation**.
   - Add a final **Refresh Data Provider** → **Letter Details** (so it matches the other buttons).

## Step 4 — Add patient for admins only

- **Navigation** → **Add patient** link → role **Admin**.
- `/newpatient` screen → **Access** **Admin**.
- `/patients` → **Add Patient Button** → Condition **Show** if `{{ [user].[roleId] }}` equals `ADMIN`.

## Step 5 — CSS

Append to **New Embed** on `/review` (pill like Status Pill) and to the embed on `/intake`:
```html
<style>
[data-name="Dolphin Tag"] > div { display: flex !important; justify-content: flex-start !important; }
[data-name="Dolphin Tag"] p {
  display: inline-block !important; width: fit-content !important; margin: 0 !important;
  font-size: 12px !important; font-weight: 500 !important; line-height: 1.4 !important;
  padding: 3px 10px !important; border-radius: 999px !important;
  color: #2E4F48 !important; background: #DCE7E4 !important;
}
[data-name="Save Hint"] p, [data-name="Input Needed Note"] p { font-size: 13px !important; color: #8A5A12 !important; margin: 0 !important; }
</style>
```

Publish.

## Step 6 — Test

1. Dolphin → a new patient → Intake: **Linked to Dolphin** tag; no parent warning wording about "one
   parent"; Consult date shows today; **Save consult** greyed out with the hint until you type a
   transcript or TMT notes.
2. Pick a referring dentist, save → Review/Letter Details shows that dentist. Try **+ Add new referring
   doctor** with a name → it appears in the picker next time.
3. Weave Test (saved empty earlier) → Review: **Regenerate all** is gone; the input form shows. Paste
   a transcript → **Save & generate letters** → the generating animation, then letters.
4. Sign in as a non-admin staff user: no **Add patient** in the menu or on Patients.
