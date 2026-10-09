# Consult — composite photo from the Letter Details card

Staff add, replace or remove the composite photo in the **Letter Details** card on `/review`.
It appears in the family letter **right under the first paragraph after the greeting**, on
screen and in the PDF and Word downloads. **Letters are not regenerated**, so edits survive.
Photos can be changed while the consult is in review; approved letters are locked.

```
Letter Details card                Postgres                         n8n
───────────────────                ────────                         ───
Composite photo (upload)  ──Save──▶ C · Save composite
                                    composite_url = new file
                                    composite_image = NULL
                                    pg_notify('consult_composite') ─▶ C03 Consult - Fetch Composite
                                                                      download file (Budibase only)
                                    composite_image = base64   ◀───── check JPEG/PNG, save
        C · Wait for composite ◀─── (returns as soon as it's stored, ≤ 12 s)
        refresh → photo shows on the Family letter tab
Download PDF / Word (C02) ─────────▶ composite_image placed after the first paragraph
```

## What changed, and what's tested

| Piece | File | Tested |
|---|---|---|
| Wait function | `01_wait_for_composite.sql` | Postgres 16: returns `ready` at once, picks up n8n's save within 1 s, `none` after removal |
| Save query | `C · Save composite.sql` | notifies n8n only when the photo really changes; same URL re-saved → no-op; remove works; approved → no change; audit rows |
| Screen split | `C · Consult review.sql` | intro ends after the first paragraph (also with a two-paragraph intro); intro + rest join back to the full letter |
| Fetch workflow | `C03_Consult_-_Fetch_Composite.json` | code nodes: relative URL → full URL, other hosts / http refused, JPEG round-trips, HTML refused |
| Downloads | `../downloads/C02_Consult_-_Download_Letter.json` | built from your live C02 export (only **Build file** changes); JPEG, RGBA / palette / 16-bit PNG in PDF and Word; doctor letters never get the photo |

PDF: the photo is centred, up to the text width and 3.6in tall, and moves to the next page if it
won't fit. Word: centred picture. JPEGs always embed. Unusual PNGs (transparency, palette) need
`zlib` in the Code node — if your n8n doesn't allow it, those PNGs still go into the Word file but
are left out of the PDF (the letter still downloads). Composites are normally JPEG.

---

## Step 1 — Database (Beekeeper, **Orthea – Voice (admin)**)

Run `01_wait_for_composite.sql`.

## Step 2 — n8n

1. **C03 (new):** Import `C03_Consult_-_Fetch_Composite.json`. Check both Postgres nodes and the
   trigger use **Postgres – Consult (consult_app)**. Save, then **Active**.
2. **C02 (update):** open **C02 Consult - Download Letter** → **Build file** node → replace all of
   its code with the **Build file** code from `../downloads/C02_Consult_-_Download_Letter.json`
   (or re-import that file over C02). Nothing else in C02 changes. Save.

## Step 3 — Budibase queries (Data → Consult DB)

1. **+ Create query** `C · Save composite` — Function **Update**. Parameters (default blank):
   `patientId`, `email`, `compositeUrl`, `removeComposite`. Paste `C · Save composite.sql`. Save
   (don't Run).
2. **+ Create query** `C · Wait for composite` — Function **Read**. Parameters: `patientId`
   (default `1`), `email` (default `lso@ortheasecurity.com`). Paste `C · Wait for composite.sql`.
   Run, Save.
3. **`C · Consult review`** — replace the whole SQL with `C · Consult review.sql`. Run, Save.
   Then check the **Consult Review** data provider on `/review` still has
   `patientId` = `{{ [state].[selectedPatientId] }}` and `email` = `{{ [user].[email] }}`.

## Step 4 — Letter Details card: Composite photo section

Select **Details Form**, add these **between Fee Months and Details Locked Note**:

| Name | Component | Settings |
|---|---|---|
| **Details Section Photo** | Text | `Composite photo — appears under the first paragraph of the family letter` |
| **Composite Photo** | Single Attachment field | Field `compositeImage`, Label blank |
| **Remove Composite** | Checkbox | Field `removeComposite`, Text `Remove the current photo` |

## Step 5 — Save buttons

**Save Details** — add after the **Execute Query `C · Save letter details`** action:

1. **Execute Query** → `C · Save composite`
   - `patientId` = `{{ [state].[selectedPatientId] }}`
   - `email` = `{{ [user].[email] }}`
   - `compositeUrl` = `{{ [c14fc273d746a43588281249b153032b1].[compositeImage].[url] }}`
   - `removeComposite` = `{{ [c14fc273d746a43588281249b153032b1].[removeComposite] }}`
2. **Execute Query** → `C · Wait for composite` (`patientId`, `email` as above)
3. **Refresh Data Provider** → **Composite Provider**
4. **Update Field Value** → Form **Details Form**, Type **Reset to default value**, Field `compositeImage`
5. **Update Field Value** → Form **Details Form**, Type **Reset to default value**, Field `removeComposite`

(keep its existing refreshes and the "Details saved" notification after these)

Actions 4–5 empty the upload box and untick **Remove the current photo** once the save is done.
The box is only a picker: the photo in the letter is what shows on the **Family letter** tab.
Ticking **Remove the current photo** takes the photo out of the letter when you press **Save
details**; it doesn't clear the picker on its own.

**Save Regen Details** — add the same three actions right after its
**Execute Query `C · Save letter details`** action (before `C · Set generating`).

## Step 6 — CSS

Append to the end of **New Embed** on `/review`:

```html
<style>
/* ===== Letter details: composite photo section, full width ===== */
[data-name="Composite Photo"], [data-name="Composite Photo"] > div,
[data-name="Remove Composite"], [data-name="Remove Composite"] > div { grid-column: 1 / -1 !important; }
[data-name="Composite Photo"] .spectrum-Dropzone { background: #FFFFFF !important; border-radius: 7px !important; }
</style>
```

## Step 7 — Test

| Do this | Expect |
|---|---|
| Review consult → pick a JPEG in Composite photo → **Save details** | "Details saved" within a few seconds; Family letter tab shows the photo under the first paragraph |
| Approve → Download family PDF and Word | photo under the first paragraph in both |
| Pick a different photo → Save | new photo replaces the old one |
| Tick **Remove the current photo** → Save | photo gone from screen and downloads |
| Save again without touching the photo | nothing changes (no re-download) |
| n8n → C03 executions | one run per photo change, ending in **Save photo** |

If the photo doesn't appear, check these in order:

1. **n8n → C03 Consult - Fetch Composite** is **Active** (toggle at the top right). The Postgres
   trigger only listens while the workflow is active; the editor's *Test workflow* button doesn't
   catch saves made in Budibase.
2. **C03 → Executions**: no run at all means the save didn't change the photo, or C03 isn't
   active. A red run shows the failing node and its error.
3. Beekeeper:
   ```sql
   SELECT id, status, left(composite_url, 70) AS url, composite_image IS NOT NULL AS has_image
   FROM consult.consults ORDER BY updated_at DESC LIMIT 3;
   ```
   `url` empty → Budibase didn't send the file (the consult must be in **review**). `url` set and
   `has_image` false → C03 couldn't fetch it.
