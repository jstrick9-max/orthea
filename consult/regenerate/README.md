# Consult — live "writing your letters" panel on `/review`

After **Regenerate all** (or **Save & regenerate**), the Generated documents card shows
an animated "Writing your letters" panel. The new letters appear on their own when n8n
finishes, with no page refresh.

## How it works

Budibase can't poll on a timer here (data provider **Auto-refresh** is a paid feature),
so the button waits instead:

```
Regenerate all
  1. C · Set generating        status → generating   (n8n C01 starts)
  2. Refresh Consult Review    card shows the panel (status = generating)
  3. C · Wait for letters  ×8  each call returns as soon as status ≠ generating,
                               or after 12 s → up to ~96 s in total
  4. Refresh Consult Review    new letters replace the panel
     Refresh Flags Provider    conflict flags update too
```

`C · Wait for letters` calls the database function `consult.wait_for_generation`, which
checks the status once a second. Once the letters are done, the remaining waits return
instantly. Each call stays under Budibase's ~15 s query time limit. It's a **Read**
query, so Budibase shows no "query executed" pop-ups.

If generation runs past ~96 s, or the page is opened while letters are still being
written, the panel stays up with a **Check again** button.

---

## Step 1: Database function (Beekeeper, admin connection)

1. Open **Orthea – Voice (admin)** (`orthea_admin`).
2. Paste and run `01_wait_for_generation.sql`.

## Step 2: New Budibase query

**Data → Consult DB → + Create query**

1. Name: `C · Wait for letters`. Function: **Read**.
2. Add two parameters, with the same defaults as `C · Consult review`:
   `patientId` (default `1`) and `email` (default `lso@ortheasecurity.com`).
3. Paste the SQL from `C · Wait for letters.sql`, click **Run** (it returns one
   `status` column), then **Save**.

## Step 3: The panel

On `/review`, in the tree: **Documents Card → Documents Card Body**.

1. Select **Documents Card Body** → **+ Add component → Container**. Rename it
   **Generating Panel** and drag it above **Letter View**.
2. Condition on **Generating Panel**: **Show component** · **Equals** · `generating`, with value:
   ```
   {{ [cf63413f4229447ef864d862c5627ee22].[rows].0.status }}
   ```
3. Select **Generating Panel** → **+ Add component → Embed**. Rename it
   **Generating Animation** and paste all of `generating-animation.html` into its
   **Embed** box.
4. Select **Generating Panel** → **+ Add component → Button**. Rename it **Check Again**,
   set Text `Check again`, and give it these **On click** actions in order:
   1. **Execute Query** → `C · Wait for letters`, with `patientId` =
      `{{ [state].[selectedPatientId] }}` and `email` = `{{ [user].[email] }}`
   2. **Refresh Data Provider** → **Consult Review**
   3. **Refresh Data Provider** → **Flags Provider**

## Step 4: Hide the letters and footer while writing

Add a second condition to each of these (keep the existing `editMode` one):

| Component | Condition |
|---|---|
| **Letter View** | **Hide component** · `{{ [cf63413f4229447ef864d862c5627ee22].[rows].0.status }}` · Equals · `generating` |
| **Documents Card Footer** | same |

Hiding the footer also stops Regenerate from being clicked twice.

## Step 5: The two regenerate buttons

### Regenerate all (**Generate Button**)

Current actions: *Execute Query (C · Set generating) → Show Notification*.
Change them to:

1. **Execute Query** → `C · Set generating`. Leave it as is.
2. Delete **Show Notification**. The panel replaces it.
3. **Refresh Data Provider** → **Consult Review**
4. **Execute Query** → `C · Wait for letters` (`patientId` =
   `{{ [state].[selectedPatientId] }}`, `email` = `{{ [user].[email] }}`)
5. Repeat step 4 **seven more times** (8 Wait actions in total).
6. **Refresh Data Provider** → **Consult Review**
7. **Refresh Data Provider** → **Flags Provider**

### Save & regenerate (**Save Regen Notes**)

Keep its current five actions and add these at the end:

1. **Execute Query** → `C · Wait for letters` ×8 (same parameters as above)
2. **Refresh Data Provider** → **Consult Review**
3. **Refresh Data Provider** → **Flags Provider**

## Step 6: Styling for the Check again button

Paste at the end of **New Embed**:

```html
<style>
/* ===== Generating panel ===== */
[data-name="Generating Panel"] > div {
  display: flex !important;
  flex-direction: column !important;
  align-items: center !important;
  padding-bottom: 32px !important;
}
[data-name="Check Again"] {
  --spectrum-button-cta-m-text-color: #1F1D1B;
  --spectrum-button-cta-m-text-color-hover: #1F1D1B;
}
[data-name="Check Again"] button {
  background: #FFFFFF !important;
  border: 1px solid #D9D0C4 !important;
  border-radius: 10px !important;
  font-size: 13px !important;
  font-weight: 500 !important;
  padding: 8px 16px !important;
  min-height: 36px !important;
  box-shadow: none !important;
}
[data-name="Check Again"] button:hover {
  background: #FAF7F3 !important;
  border-color: #BFB5A7 !important;
}
</style>
```

## Step 7: Test, then publish

| Do this | Expect |
|---|---|
| Regenerate all | Letters and footer disappear; "Writing your letters" panel animates |
| Wait ~1 min | Panel disappears, new letters show, flags update. No refresh needed. |
| Edit TMT notes → Save & regenerate | Same |
| Refresh the page mid-generation | Panel shows; **Check again** brings the letters in once ready |

If an action shows a timeout error, Budibase's query limit on your install is shorter
than 15 s. Tell me and I'll lower the 12 s wait.
