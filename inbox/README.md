# Orthea Inbox (demo build)

Doctors forward a voice note, photo or text to their practice's inbox address; Orthea transcribes
it, finds the patient, drafts a chart note, and staff copy the note into the chart.
Orthea never writes to Dolphin.

```
doctor's phone ─email─▶ lso.inbox@ortheasecurity.com (Spacemail)
     n8n E01 (IMAP) ─▶ inbox.receive()  → stored once; unknown senders held
                    ─▶ attachments to S3, transcribe, AI: patient + summary + chart note
                    ─▶ inbox.complete() → patient matched (name+DOB, name, last+DOB)
Budibase  Inbox screen ─▶ check patient, Copy note, Filed / Dismiss
```

## Naming

Like Consult's `C · …` queries and `C01 …` workflows, everything of Inbox starts with **E**:
Budibase queries `E · Inbox list`, `E · File item`, …; n8n workflows `E01 Inbox - Receive`, …
Database: schema `inbox`, user `inbox_app`.

## A separate product

| Layer | Inbox | Shared with Consult / Voice |
|---|---|---|
| Budibase | its own app **Orthea Inbox** (own screens, nav, URL, roles) | the workspace and user logins |
| Budibase data source | its own **Inbox DB**, signed in as `inbox_app` | — |
| Postgres | its own schema `inbox`, own user `inbox_app` | reads `consult.patients` (id, name, DOB, Dolphin ID only) and `public.practice_users` to scope by practice |
| n8n | its own workflows `E01 …`, own Postgres credential (`inbox_app`) | the n8n instance, S3 and AI credentials |
| Mail | per-practice inbox mailbox (`lso.inbox@`) | — |

`inbox_app` cannot see consults, letters, flags or anything of Voice (tested).
The patient list is the one shared piece: Inbox must know the practice's patients to match a
message. If Inbox is ever sold to a practice without Consult, that list moves to a shared
`public.patients` table; nothing in Inbox's screens changes.

**Demo rule: made-up patients and recordings only** until BAAs are signed with the
transcription and AI providers.

| Step | What | Status |
|---|---|---|
| 1 | Database: `00_inbox_role.sql`, `01_inbox.sql`, `02_lso_setup.sql` | built, tested (`tests/run.sh`, 20 checks) |
| 2 | n8n `E01 Inbox - Receive` + `E02 Inbox - Process` | built, code tested (`n8n/tests/run.mjs`, 30 checks); needs a live run |
| 3 | Budibase app **Orthea Inbox** + data source **Inbox DB** | queries tested (`tests/budibase.sh`, 22 checks); screens: steps below |
| 4 | Demo recordings | after 3 |

## Step 1 — database (Beekeeper, admin connection, Auto Commit)

0. Open `00_inbox_role.sql`, replace `CHANGE-ME` with a new strong password (password manager),
   run it. This is Inbox's own database user.
1. Run `01_inbox.sql`. The last result shows 3 tables and 2 functions.
2. Open `02_lso_setup.sql`, replace `YOUR.EMAIL@example.com` with the address(es) you'll send
   test notes from (one line each), then run it. Only these senders are processed; anything
   else sent to the inbox is held.

Matching only ever looks at the practice the inbox address belongs to. Two patients with the
same name and no birthday in the message are left for staff to pick.

## Step 2 — n8n

```
E01 Inbox - Receive   IMAP (lso.inbox@) → parse → inbox.receive() → attachments to S3 → pg_notify('inbox_process', id)
E02 Inbox - Process   LISTEN inbox_process → load message → Amazon Transcribe (voice note) → Claude on Bedrock
                      (same model as Consult) → inbox.complete()   ·   any failure → inbox.complete(error)
```

All AWS calls are signed in Code nodes with `INBOX_AWS_KEY` / `INBOX_AWS_SECRET` (the
`orthea-inbox-n8n` IAM user), like C01 does with the Consult keys. Bucket: `INBOX_BUCKET` if set,
otherwise `orthea-inbox`. Successful runs aren't saved in n8n's execution list (they carry patient
details); failed runs are.

Voice notes Transcribe can read: m4a (iPhone Voice Memos), mp3, mp4, wav, flac, ogg/opus (WhatsApp),
amr, webm. Others (e.g. .caf from iMessage) are stored and listed, and the chart note says the
voice note couldn't be transcribed.

1. n8n → **Create workflow → ⋯ → Import from file** → `E01_Inbox_-_Receive.json`. Open **New email**:
   credential **IMAP – LSO Inbox**. Open **Receive** and **Hand to E02**: credential
   **Postgres – Inbox (inbox_app)**. Save.
2. Same for `E02_Inbox_-_Process.json`: **Process requested**, **Load item**, **Save**, **Record error** →
   **Postgres – Inbox (inbox_app)**. Save.
3. Turn **E02** on first (Active / Publish), then **E01**.
4. From jstrick9@gmail.com, email lso.inbox@ortheasecurity.com with a made-up voice memo (iPhone
   Voice Memos → Share → Mail) about a demo patient, e.g. *"Leo Marsh, born August 27 2013 — the
   upper left molar extraction went well, he can start the expander next week."*
5. Within about a minute (E01 checks the mailbox every minute) check in Beekeeper:
   ```sql
   SELECT id, status, from_email, match, patient_id, summary, chart_note, error
     FROM inbox.items ORDER BY id DESC LIMIT 5;
   ```
   Expect `status = new`, `match = name_dob`, a summary and a chart note. `error` says what failed
   otherwise.

Rebuild after editing `n8n/src/*.js`: `node inbox/n8n/build.mjs`; tests: `node inbox/n8n/tests/run.mjs`.

## Step 3 — Budibase app **Orthea Inbox**

Bindings below are written the readable way (`{{ Item.Rows.0.chart_note }}`); the easiest way to
enter one is the ⚡ drawer: pick the component (e.g. **Item**), then **Rows → 0 → the field**.

### A. Data source and queries
1. **Data → + Add source → PostgreSQL**, name **Inbox DB**. Same host, port, database and SSL setting
   as **Consult DB**; user `inbox_app` and its password. Save (no need to fetch tables).
2. For each file in `budibase/`, **+ Create query** on **Inbox DB** with that name, Function as the
   file's first line says, the parameters it lists (Default blank), paste the SQL, **Run**, **Save**:
   `E · Inbox list`, `E · Inbox item`, `E · Inbox patients` (Read);
   `E · Set patient`, `E · Save note`, `E · File item`, `E · Dismiss item`, `E · Reopen item` (Update).

### B. The app
In the workspace: **+ New app** → **Orthea Inbox**, URL `inbox`. Navigation **Left**, background
`#F7F3EE`, text `#1F1D1B`, hover `#E8E1D7` / `#2F4A43`, active `#DCE7E4` / `#2F4A43`, **Hide title** on.
One link: **Inbox** → `/inbox`, role Basic.

### C. Screen `/inbox` (home screen)
1. **+ Add screen → Blank**, route `/inbox`, access **Basic**, tick **Set as home screen**.
2. **Embed** `New Embed`: paste all of `inbox-embed.html`.
3. **On screen load**: Update State `inboxView` = `new` (Persist off).
4. **Container** `Inbox Container` with:
   - **Container** `Inbox Header` with **Text** `Inbox Title` = `Inbox`, and **Container** `Inbox Tabs`
     holding four **Buttons**: `Tab New` "To file", `Tab Filed` "Filed", `Tab Held` "Set aside",
     `Tab All` "All". Each: Variant **Secondary**; On click → Update State `inboxView` = `new` / `filed` /
     `held` / `all`; Condition **Update setting → Variant = Action (cta)** if `{{ [state].[inboxView] }}`
     equals its value.
   - **Data Provider** `Inbox List`: `E · Inbox list`, `email` = `{{ [user].[email] }}`,
     `view` = `{{ [state].[inboxView] }}`.
   - Inside it **Container** `Inbox Card` → **Repeater** `Inbox Repeater` (provider Inbox List,
     empty text `Nothing here.`) → **Container** `Inbox Row`, On click → Navigate To
     `/item/{{ Inbox Repeater.id }}`. In the row, five **Text**s:
     `Row When` `{{ Inbox Repeater.received }}` · `Row From` `{{ Inbox Repeater.sender }}` ·
     `Row Patient` `{{ Inbox Repeater.patient_label }}` · `Row Summary` `{{ Inbox Repeater.summary }}` ·
     `Row Status` `{{ Inbox Repeater.status_label }}`.
     Row Status conditions (Update setting → **Custom CSS**):
     equals `Needs a look` → `--pill-bg: #FDF4E7; --pill-fg: #8A6A2F;` ·
     equals `Filed` → `--pill-bg: #F1EFE8; --pill-fg: #6B6460;`.

### D. Screen `/item/:id`
1. **+ Add screen → Blank**, route `/item/:id`, access **Basic**. Not in the navigation.
2. **Embed**: the same `inbox-embed.html`.
3. **Data Provider** `Item`: `E · Inbox item`, `id` = `{{ url.id }}`, `email` = `{{ [user].[email] }}`.
   **Data Provider** `Patients` (next to it): `E · Inbox patients`, `email` = `{{ [user].[email] }}`.
4. Inside **Item**, **Container** `Item Container` with:
   - **Container** `Item Header`: **Button** `Item Back` "Back to Inbox" (Secondary, Navigate To `/inbox`),
     **Text** `Item Title` = `{{ Item.Rows.0.summary }}`, **Text** `Item Status` = `{{ Item.Rows.0.status_label }}`.
   - **Text** `Item Meta` = `From {{ Item.Rows.0.sender }} · {{ Item.Rows.0.received }}`.
   - **Container** `Item Columns` with two containers:

   **`Note Card`**
   - **Text** `Note Card Title` = `Patient and chart note`.
   - **Form** `Item Form` (Custom) containing:
     - **Options Picker** `Patient Picker`: field `patientId`, label `Patient`, options from data
       provider **Patients**, label column `label`, value column `id`,
       default `{{ Item.Rows.0.patient_id }}`, placeholder `Pick the patient`.
     - **Text** `Match Note` = `{{ Item.Rows.0.match_label }}`.
     - **Text** `Message Says` = `The message names: {{ Item.Rows.0.message_names }}`;
       Condition Hide if `{{ Item.Rows.0.message_names }}` equals (blank).
     - **Long Form Field** `Chart Note`: field `chartNote`, label `Chart note`,
       default `{{ Item.Rows.0.chart_note }}`.
     - **Container** `Note Actions` (Condition: Show if `{{ Item.Rows.0.status }}` equals `new`) with Buttons:
       - `Copy Note` "Copy note" (Secondary): **Copy To Clipboard** `{{ Item Form.Value.chartNote }}`
         (⚡ → Item Form → chartNote), then Show Notification "Copied".
       - `Save Note` "Save" (Secondary): Execute Query `E · Set patient` (`id` `{{ url.id }}`,
         `email` `{{ [user].[email] }}`, `patientId` = form chartNote's sibling `patientId`) →
         Execute Query `E · Save note` (`id`, `email`, `chartNote` = form `chartNote`) →
         Refresh Data Provider **Item** → Show Notification "Saved". Tick **Do not display default
         notification** on both queries.
       - `File Note` "Mark as filed" (Action): Execute Query `E · Set patient` (as above) →
         Execute Query `E · File item` (`id`, `email`, `chartNote`) → Show Notification "Filed" →
         Navigate To `/inbox`. Condition **Update setting → Disabled = true** if form `patientId`
         equals (blank).
       - `Dismiss Note` "No note needed" (Secondary): Execute Query `E · Dismiss item` (`id`, `email`),
         **Require confirmation** ("Set this message aside without a chart note?") → Navigate To `/inbox`.
     - **Container** `Closed Box` (Show if status equals `filed`, and a second condition Show if equals
       `dismissed`): **Text** `Closed Text` = `Done by {{ Item.Rows.0.filed_by }} on {{ Item.Rows.0.filed_on }}.`,
       **Button** `Reopen` "Reopen" (Secondary): `E · Reopen item` (`id`, `email`) → Refresh **Item**.
     - **Container** `Held Box` (Show if status equals `held`): **Text** `Held Text` =
       `From a sender not on the approved list, so it was not processed.`, **Button** `Held Dismiss`
       "Set aside": `E · Dismiss item` → Navigate To `/inbox`.
     - **Container** `Error Box` (Show if status equals `error`): **Text** `Error Text` =
       `Orthea could not process this message: {{ Item.Rows.0.error }}`.

   **`Source Card`**
   - **Text** `Source Card Title` = `Message`.
   - **Text** `Source Label Subject` = `Subject`, **Text** `Source Text Subject` = `{{ Item.Rows.0.subject }}`.
   - **Text** `Source Label Files` = `Attachments`, **Text** `Source Text Files` = `{{ Item.Rows.0.attachment_names }}`
     (both: Hide if attachment_names equals blank).
   - **Text** `Source Label Transcript` = `Voice note`, **Text** `Source Text Transcript` = `{{ Item.Rows.0.transcript }}`
     (both: Hide if transcript equals blank).
   - **Text** `Source Label Body` = `Email text`, **Text** `Source Text Body` = `{{ Item.Rows.0.body_text }}`.

5. Publish the app.

### E. Test
1. Inbox → **To file** lists the test messages, newest first; Leo Marsh shows his name.
2. Open it: Patient = Leo Marsh, "Matched on name and date of birth"; the chart note and email text show.
3. **Copy note** → paste in Notepad. Edit the note, **Save**, refresh: the edit stays.
4. **Mark as filed** → back on the Inbox; **Filed** tab shows it; open it → "Done by … on …", **Reopen** works.
5. The Ava message (no birthday): Patient empty, **Mark as filed** greyed until you pick her.
6. **Set aside** tab: the Spacemail welcome message, "not processed".

Attachments are listed by name only for now; viewing / playing them comes next (a short-lived link
from n8n, since the bucket is private).
