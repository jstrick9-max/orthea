# Consult — patient in the screen address (one patient per tab)

**Problem:** `selectedPatientId` was set with **Persist** on. Persisted state is shared by every tab,
so picking a patient in one tab switched all the others — and a Save in a stale tab would act on
the other tab's patient.

**Fix:** the patient's ID goes in the address — `#/review/17`, `#/intake/17`. Review and Intake copy
`{{ url.id }}` into `selectedPatientId` when they open, **without Persist**, so the value lives in that
tab only. The 46 existing `{{ [state].[selectedPatientId] }}` bindings on Review and Intake don't
change. Refresh and bookmarks keep the patient.

Mapped from the 2026-10-10 export: 43 bindings on `/review`, 3 on `/intake`, setters on `/patients`,
`/launch/:t`, `/dolphin`, plus the two navigations into Review/Intake.

## Steps (Consult app, builder)

### 1. `/review`
- Screen settings → **Route** `/review/:id`.
- **On screen load** → **Add Action** → **Update State**: Set `selectedPatientId`, Value
  `{{ url.id }}`, **Persist off**. Drag it to the top (above the existing `reviewTab` action).
- **New Consult Button** → On click → Navigate To → URL `/intake/{{ [state].[selectedPatientId] }}`.

### 2. `/intake`
- Route `/intake/:id`.
- **On screen load** → Update State: `selectedPatientId` = `{{ url.id }}`, **Persist off**.
- **Save Consult Button** → action 5 Navigate To → URL `/review/{{ [state].[selectedPatientId] }}`.

### 3. `/patients` — **Row Main** → On click
- Delete action 1 (**Update State** `selectedPatientId`).
- Navigate To → URL
  `{{ [c887586b533004f3db2e402f41ce6fffc].[destination] }}/{{ [c887586b533004f3db2e402f41ce6fffc].[id] }}`

### 4. `/launch/:t` and `/dolphin` — On screen load
- Delete the **Update State** `selectedPatientId` action (5 on `/launch/:t`, 6 on `/dolphin`).
- **Navigate To** → URL → ⚡ JavaScript:
  ```js
  const r = $("actions.1.result");
  const rows = Array.isArray(r) ? r : ((r && (r.data || r.rows)) || []);
  return (rows[0] && rows[0].destination) ? rows[0].destination + "/" + rows[0].patient_id : "";
  ```

### 5. Publish

## Test (two tabs)

1. Patients → open patient A → address ends `#/review/<A>` (or `/intake/<A>`).
2. New tab → Patients → open patient B. Go back to the first tab: still patient A.
3. In tab A, change a Letter Details field and **Save details**; check it saved on A, not B.
4. Refresh tab A → still patient A.
5. Dolphin test address → opens `#/intake/<id>` or `#/review/<id>`.
6. Intake → **Save consult** → lands on `#/review/<same id>`. Review → **New consult** → `#/intake/<same id>`.

Old links to plain `#/review` or `#/intake` no longer match a screen and fall back to Patients.
