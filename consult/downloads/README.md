# Consult — Download PDF / Word for approved letters

Adds **Download PDF** and **Download Word** to the Generated documents card on
`/review`. They appear only once the letters are approved, only on the Doctor letter and
Family letter tabs (never on TMT summary), and the files carry the same LSO letterhead
and address footer as the card.

See `samples/` for what the files look like (fictional Leo Marsh letters).

## How it works

```
Budibase /review                    n8n  C02 Consult - Download Letter          Postgres (consult schema)
────────────────                    ──────────────────────────────────          ─────────────────────────
[Download PDF] ── opens link ──▶  GET /webhook/7c3f9a52-…/consult/letter/<token>/<doctor|family>/<pdf|docx>
                                    1. Load approved letter  ──────────────────▶ consults.download_token = <token>
                                                                                 AND status = approved
                                    2. Letter found?  ── no ──▶ "This download isn't available" page
                                    3. Build file (PDF or .docx, letterhead built in)
                                    4. Send file  ◀── browser downloads it
                                    5. Log download ───────────────────────────▶ consult.audit_log
```

- **The link token.** Approving a consult now stores a random 64-character
  `download_token`. Reopening clears it, so old links stop working, and approving again
  issues a new one. The link works only while the consult is approved.
- **Text used.** The edited letter if there is one, otherwise the generated draft, laid
  out exactly as on screen.
- **Date line.** The approval date (e.g. "October 6, 2026") goes above the greeting,
  as on a mailed letter. The card itself doesn't show it.
- **No new services.** The files are built inside the n8n Code node, in plain
  JavaScript with no add-ons. The letterhead images are embedded in the node.
  C02 uses only the `Postgres – Consult (consult_app)` credential and touches nothing
  in Voice.
- **Audit.** Each download adds `downloaded doctor_letter pdf` (etc.) to
  `consult.audit_log`, with the Budibase user's email as the actor. The email comes
  from the link, so treat it as a record, not proof.

---

## Step 1: Database (Beekeeper, admin connection)

Schema changes need the admin connection.

1. In Beekeeper, open **Orthea – Voice (admin)** (`orthea_admin`).
2. Open `sql/01_add_download_token.sql`, paste it all, and run it.
3. The last statement lists approved consults. Each should show the start of a token.
   An empty list just means nothing is approved yet.

`gen_random_uuid()` needs Postgres 13 or newer. If you get "function
gen_random_uuid() does not exist", run `SELECT version();` and send me the result.

## Step 2: n8n, import the workflow

1. In n8n, go to **Workflows → Add workflow → ⋯ → Import from File** and choose
   `C02_Consult_-_Download_Letter.json`.
2. Open **Load approved letter** and **Log download**, and check that both use the
   credential **Postgres – Consult (consult_app)**. Pick it from the list if either
   shows a warning.
3. Open **Download requested** and switch to **Production URL**. It should be:
   ```
   https://listen.ortheasecurity.com/webhook/7c3f9a52-4e1d-4b8a-9f6e-2d5c8b1a0e47/consult/letter/:token/:doc/:format
   ```
   If the long ID in the middle is different, note yours. You'll use it in Step 4
   instead of `7c3f9a52-4e1d-4b8a-9f6e-2d5c8b1a0e47`.
4. **Save** the workflow, then turn it **Active**.

## Step 3: Budibase, update three queries

In the **Consult** app, go to **Data → Consult DB**. For each query below, open it,
replace the **whole SQL** with the file's contents (comment lines included are fine),
and **Save**. Each one is your current query plus one change.

| Query | File | Change |
|---|---|---|
| `C · Approve consult` | `sql/C · Approve consult.sql` | issues a download token on approval |
| `C · Reopen consult` | `sql/C · Reopen consult.sql` | clears the token |
| `C · Consult review` | `sql/C · Consult review.sql` | returns `download_token` |

For **C · Consult review**, click **Run** before saving, so Budibase picks up the new
`download_token` column. Leave the default parameter values as they are.

## Step 4: Budibase, add the buttons on `/review`

### 4a. The container

1. **Design → /review**. In the tree, open **Documents Card → Documents Card Footer**
   and click **Documents Card Footer**.
2. **+ Add component → Container**. Rename it **Download Buttons**.
3. Drag it so it sits directly below **Approval Note**, above **Edit Buttons**.
4. **Configure conditions → Add condition**:
   **Show component** · if `approve_state` (binding picker: **Consult Review → rows → 0 →
   approve_state**) · **Equals** · `done` → **Save**.

### 4b. The four buttons

With **Download Buttons** selected, add four **Buttons** (**+ Add component → Button**,
four times). Set each one up as in the table, then follow the click steps below it.

| Name | Text | Link ends with | Condition |
|---|---|---|---|
| **Download Doctor PDF** | `Download PDF` | `/doctor/pdf?by=…` | **Hide** if `{{ State.reviewOther }}` Equals `yes` |
| **Download Doctor Word** | `Download Word` | `/doctor/docx?by=…` | **Hide** if `{{ State.reviewOther }}` Equals `yes` |
| **Download Family PDF** | `Download PDF` | `/family/pdf?by=…` | **Show** if `{{ State.reviewTab }}` Equals `family` |
| **Download Family Word** | `Download Word` | `/family/docx?by=…` | **Show** if `{{ State.reviewTab }}` Equals `family` |

These are the same conditions your Edit Doctor and Edit Family buttons use. On the TMT
summary tab, none of the four shows.

For each button:

1. Rename it (double-click in the tree) and set **Text**. Leave **Variant** on
   **Action**, like the other footer buttons. *Optional:* set **Icon** to `file-pdf` or
   `file-doc`.
2. **On click → Add action → Navigate To**. Choose **URL** (not Screen), turn on
   **Open in new tab**, and paste the matching link:

   ```
   https://listen.ortheasecurity.com/webhook/7c3f9a52-4e1d-4b8a-9f6e-2d5c8b1a0e47/consult/letter/{{ [cf63413f4229447ef864d862c5627ee22].[rows].0.download_token }}/doctor/pdf?by={{ [user].[email] }}
   ```
   ```
   https://listen.ortheasecurity.com/webhook/7c3f9a52-4e1d-4b8a-9f6e-2d5c8b1a0e47/consult/letter/{{ [cf63413f4229447ef864d862c5627ee22].[rows].0.download_token }}/doctor/docx?by={{ [user].[email] }}
   ```
   ```
   https://listen.ortheasecurity.com/webhook/7c3f9a52-4e1d-4b8a-9f6e-2d5c8b1a0e47/consult/letter/{{ [cf63413f4229447ef864d862c5627ee22].[rows].0.download_token }}/family/pdf?by={{ [user].[email] }}
   ```
   ```
   https://listen.ortheasecurity.com/webhook/7c3f9a52-4e1d-4b8a-9f6e-2d5c8b1a0e47/consult/letter/{{ [cf63413f4229447ef864d862c5627ee22].[rows].0.download_token }}/family/docx?by={{ [user].[email] }}
   ```
   Budibase will show the bindings as readable names (Consult Review…, Current User…).
   If you'd rather build them with the ⚡ picker, use **Consult Review → rows → 0 →
   download_token** and **Current User → email**.
3. **Configure conditions** → add the condition from the table → **Save**.

### 4c. Styling

Select **New Embed** (first item under Blank screen) and paste this at the end of the
**Embed** box:

```html
<style>
/* ===== Download buttons (approved letters) ===== */
[data-name="Download Buttons"] {
  --spectrum-button-cta-m-text-color: #1F1D1B;
  --spectrum-button-cta-m-text-color-hover: #1F1D1B;
}
[data-name="Download Buttons"] > div {
  display: flex !important;
  flex-direction: row !important;
  align-items: center !important;
  gap: 10px !important;
}
[data-name="Download Buttons"] button {
  background: #FFFFFF !important;
  border: 1px solid #D9D0C4 !important;
  border-radius: 10px !important;
  font-size: 13px !important;
  font-weight: 500 !important;
  padding: 8px 16px !important;
  min-height: 36px !important;
  box-shadow: none !important;
}
[data-name="Download Buttons"] button .spectrum-Button-label {
  color: #1F1D1B !important;
  -webkit-text-fill-color: #1F1D1B !important;
}
[data-name="Download Buttons"] button:hover {
  background: #FAF7F3 !important;
  border-color: #BFB5A7 !important;
}
</style>
```

## Step 5: Test, then publish

In **Preview**, open Leo Marsh (or any consult in review):

| Do this | Expect |
|---|---|
| Before approving | No download buttons |
| Approve letters | Footer shows: *Approved by … · Download PDF · Download Word · Reopen for edits* |
| Doctor letter → Download PDF / Word | `Leo Marsh - Doctor Letter.pdf` / `.docx` downloads, with letterhead and footer |
| Family letter → Download PDF / Word | `Leo Marsh - Family Letter.pdf` / `.docx` |
| TMT summary tab | No download buttons |
| Reopen for edits, then open an old download link | "This download isn't available" page |

Then check the log in Beekeeper:

```sql
SELECT consult_id, action, actor, created_at
FROM consult.audit_log ORDER BY created_at DESC LIMIT 10;
```

When it all checks out, **Publish** the Consult app.

---

## Changing the letterhead

The header and footer images are rendered from the same HTML/CSS as the on-screen
letterhead, then embedded in the n8n Code node. To change them (new doctor, new
address), edit the markup in `tools/render-letterhead.mjs`, then:

```
NODE_PATH=$(npm root -g) node consult/downloads/tools/render-letterhead.mjs
python3 consult/downloads/tools/whiten.py
node consult/downloads/tools/build-workflow.mjs
node consult/downloads/tools/test.mjs
```

Re-import `C02_Consult_-_Download_Letter.json`, or paste the new Code node source over
**Build file**. When Consult goes to a second practice, the images should move to
per-practice storage (e.g. `consult.practice_settings`) instead of living in the node.

## Files

| Path | What |
|---|---|
| `C02_Consult_-_Download_Letter.json` | n8n workflow to import (generated, don't hand-edit) |
| `sql/` | Database change and the three updated Budibase queries |
| `src/render.js` | PDF and .docx builder (no dependencies) |
| `src/code-node.js` | The n8n Code node glue around it |
| `assets/` | Letterhead header and footer PNGs |
| `tools/` | Render letterhead, build the workflow, test |
| `samples/` | Example output |
