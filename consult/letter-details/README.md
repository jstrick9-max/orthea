# Consult — Letter Details card on `/review`

Implements `orthea-consult-letter-details-reference-2026-10-09.md` (decisions, scope, component
spec). This folder has the **tested** SQL and the build steps. Where the files here differ from
the reference doc's drafts, use these.

## Changes from the reference doc's draft SQL

Both drafts were run against Postgres 16 with mock `consult` tables. The draft save query
handled every scenario correctly except two:

| | Draft | Fixed here |
|---|---|---|
| **Fee months** | Strips the decimal point, so an untouched re-save of `24.00` became **2400 months** (whenever the fee columns store decimals) | Months are parsed as a number and rounded: `24`, `24.00` and `24 months` all give 24 |
| **Patient with no dentist yet** | Picking a dentist and typing their address in the same save dropped the address | The address goes to the newly picked dentist, but only if that dentist belongs to the same practice |
| **Fee display** | `C · Letter details` returned `6860.00`, `24.00` | Returns `6860`, `24` (`trim_scale`) |

Scenarios checked: unchanged re-save; blank names keep; blank fee clears; `$6,860` parses;
re-link doesn't touch either dentist's address; another practice's dentist ID ignored;
`__new` keeps the current dentist; approved consult → no writes; another practice's user
→ no writes; audit row per save.

## Build steps (one at a time — verify before the next)

IDs used below (from the 2026-10-09 export):
`Consult Review` = `cf63413f4229447ef864d862c5627ee22`, `Flags Provider` = `c2ae6339df8604b8097258aa6b1d1ae3e`.

### Step 1 — Query `C · Letter details`

**Data → Consult DB → + Create query**
1. Name `C · Letter details`, Function **Read**.
2. Parameters: `patientId` (default `1`), `email` (default `lso@ortheasecurity.com`).
3. Paste `C · Letter details.sql`. **Run**. Check: one row with the test patient's parents,
   addresses, dentist and fees (whole numbers, e.g. `6860`, `24`). **Save**.

### Step 2 — Card shell, providers and fields (display only)

On `/review`, select **Review Rail** and build this tree. Drag **Details Card** so it sits
**between Inputs Card and Flags Card**.

```
Details Card                Container
├─ Details Card Header      Container
│  └─ Details Card Title    Text: Letter details
└─ Details Card Body        Container
   └─ Letter Details        Data Provider → C · Letter details
      ├─ Ref Doctors        Data Provider → C · Referring doctors
      └─ Details Form       Form (Type: Create)
         ├─ Details Section Family    Text: Family
         ├─ Parent 1 First            Text Field      field parent1First
         ├─ Parent 1 Last             Text Field      field parent1Last
         ├─ Parent 2 First            Text Field      field parent2First
         ├─ Parent 2 Last             Text Field      field parent2Last
         ├─ Family Address            Long Form Field field mailingAddress
         ├─ Details Section Referrer  Text: Referring dentist
         ├─ Referrer Picker           Options Picker  field refId
         ├─ Referrer Address          Long Form Field field refAddress
         ├─ Details Section Fees      Text: Fees — leave blank to leave fees out of the letter
         ├─ Fee Total                 Number Field    field feeTotal
         ├─ Fee Initial               Number Field    field feeInitial
         ├─ Fee Monthly               Number Field    field feeMonthly
         ├─ Fee Months                Number Field    field feeMonths
         ├─ Details Locked Note       Text: Locked after approval. Reopen for edits to change details.
         └─ Details Actions           Container
            ├─ Save Details           Button: Save details
            └─ Save Regen Details     Button: Save & regenerate
```

**Provider parameters**
- **Letter Details**: `patientId` = `{{ [state].[selectedPatientId] }}`, `email` = `{{ [user].[email] }}`
- **Ref Doctors**: `email` = `{{ [user].[email] }}`

**Field defaults.** Paste each into the field's **Default value**, after selecting the Letter
Details provider in the tree to look up its ID. Every binding has this form:
`{{ [<Letter Details id>].[rows].0.<column> }}`

| Field | column |
|---|---|
| Parent 1 First / Last | `parent1_first_name` / `parent1_last_name` |
| Parent 2 First / Last | `parent2_first_name` / `parent2_last_name` |
| Family Address | `mailing_address` |
| Referrer Picker | `referring_doctor_id` |
| Referrer Address | `referring_address` |
| Fee Total / Initial / Monthly / Months | `fee_total` / `fee_initial` / `fee_monthly` / `fee_months` |

**Referrer Picker**: Options source **Data provider** → **Ref Doctors**, Label column
`full_name`, Value column `id`. (The `+ Add new referring doctor` row is ignored in v1 —
picking it keeps the current dentist.)

**Conditions**
- **Details Locked Note**: **Show** · `{{ [<Letter Details id>].[rows].0.can_edit }}` · **Not equals** · `yes`
- **Details Actions**: **Show** · same value · **Equals** · `yes`

**CSS**: paste `details-card.css` as a new block at the very end of **New Embed**.

Check (published tab, hard refresh): card sits between the two rail cards, fields are filled
for the test patient, two-column name grid. The grid selector depth
(`[data-name="Details Form"] > div > div`) is a best guess — if fields stack in one
column, inspect the form in DevTools and tell me what wraps the fields.

### Step 3 — Query `C · Save letter details` + Save details button

1. **+ Create query** → `C · Save letter details`, Function **Update**.
   Parameters (all default blank): `patientId`, `email`, `parent1First`, `parent1Last`,
   `parent2First`, `parent2Last`, `mailingAddress`, `refId`, `origRefId`, `refAddress`,
   `feeTotal`, `feeInitial`, `feeMonthly`, `feeMonths`.
   Paste `C · Save letter details.sql`. **Save** (don't Run it — it writes).
2. **Save Details** → On click:
   1. **Validate Form** → Details Form
   2. **Execute Query** → `C · Save letter details`:
      - `patientId` = `{{ [state].[selectedPatientId] }}`, `email` = `{{ [user].[email] }}`
      - `origRefId` = `{{ [<Letter Details id>].[rows].0.referring_doctor_id }}`
      - every other parameter = the matching **Details Form** field (binding picker →
        Details Form → `parent1First`, … `feeMonths`)
   3. **Refresh Data Provider** → Letter Details
   4. **Refresh Data Provider** → Consult Review
   5. **Show Notification** (success): `Details saved`

Check in Beekeeper after a save: `consult.patients`, `consult.referring_doctors`,
`consult.consults` (fees) and `consult.audit_log` ("edited letter details").

### Step 4 — Save & regenerate button

**Save Regen Details** → On click:
1. **Validate Form** → Details Form
2. **Execute Query** → `C · Save letter details` (same parameters as Step 3). Turn on
   **Confirm**: *"This saves the details and regenerates all letters, replacing any edits
   you made to them."*
3. **Execute Query** → `C · Set generating` (`patientId`, `email`)
4. **Refresh Data Provider** → Consult Review  *(the Writing-your-letters panel appears)*
5. **Execute Query** → `C · Wait for letters` ×8 (`patientId`, `email`)
6. **Refresh Data Provider** → Consult Review
7. **Refresh Data Provider** → Flags Provider
8. **Refresh Data Provider** → Letter Details

Check: the regenerated letters use the edited parents/addresses/fees, and clearing a fee
removes the Fees section.

### Step 5 — Publish (when you're ready)

## Also from the export

- `C · Archived patients` now declares `email` (fixed), but its schema is still empty —
  open it, **Run**, **Save**, then re-set `email` = `{{ [user].[email] }}` on the `/archive`
  provider.
- `/review` embed: the stray extra `</style>` (after the Download Buttons block) is still
  there; harmless.
