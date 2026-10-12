# Orthea Inbox — reference for a new chat (as of 2026-10-12)

Paste or attach this file at the start of a new chat. It has no passwords or keys; never paste those into a chat.

## 1. What it is
Doctor-to-doctor messages (e.g. Dr. Neugarten, oral surgeon → Dr. Marc Lemchen) normally arrive by text/voice note, and the office manager (Romina) re-emails them to herself and notes the chart in DDO (Dolphin). **Orthea Inbox** removes that step: the doctor forwards the voice note / photo / text by email to the practice's inbox address; Orthea stores it, transcribes the voice note, drafts a one-line summary and a chart note, and staff review, correct, **Copy note**, and mark it **Filed**.

- Customer: Lemchen-Salzer Orthodontics (LSO). Future practices get their own address (e.g. `bronsky.inbox@ortheasecurity.com`) plus rows in the tables below.
- **Separate product** from Orthea Consult and Orthea Voice (own Budibase app, own DB user, own n8n workflows, own prefix **E**). **Inbox is on an island: it does not read or match Consult's patients.** The patient is whatever the message names (first name, last name, birthday), and staff correct it. Matching against a patient directory is a possible future feature.
- Orthea never writes to Dolphin. Demo rule: made-up patients/recordings only until BAAs cover every service in the chain (AWS BAA is accepted; covers Bedrock, Transcribe, S3).

## 2. Where everything is
- Repo: `jstrick9-max/orthea`, branch `claude/youthful-darwin-gt9zd7`, folder `inbox/` (plus `brand/logos/` for logos). No PR (only create one if asked).
- Stack: Postgres on RDS (database `orthea`), n8n 2.x (https://orthea-n8n.ok5nlj.easypanel.host), Budibase 3.37.1 self-hosted (https://orthea-budibase.eqawdd.easypanel.host), Easypanel, AWS us-east-2, Spacemail mailbox.
- Files:
  - `inbox/00_inbox_role.sql` — creates DB user `inbox_app`
  - `inbox/01_inbox.sql` — schema `inbox` (tables, `receive`, `complete`, grants)
  - `inbox/02_lso_setup.sql` — LSO address + approved senders
  - `inbox/03_fix_setup.sql` — placeholder password/sender fix-up (already used)
  - `inbox/04_island.sql` — removes all Consult dependence (patient_first/last/dob, new `complete()`, REVOKE on consult)
  - `inbox/n8n/` — `E01_Inbox_-_Receive.json`, `E02_Inbox_-_Process.json`, `build.mjs`, `src/*.js` (Code-node sources), `tests/run.mjs` (30 checks)
  - `inbox/budibase/` — `E · …sql` queries, `inbox.css`, `inbox-embed.html` (shared Consult shell + Inbox styles)
  - `inbox/tests/` — `run.sh` (DB, 20 checks), `budibase.sh` (queries as `inbox_app`, 23 checks); need throwaway Postgres 16 on `/tmp/pgt` port 5499
  - `consult/budibase/check-sql.js` — flags SQL Budibase would mis-parameterise (see gotchas)
  - `brand/` — `build_logos.py`, `render.cjs`, `logos/` (Inbox: `orthea-inbox*.png/svg`, `inbox-icon-*`, `inbox-favicon-*`)

## 3. Architecture
```
doctor's phone ─email→ lso.inbox@ortheasecurity.com (Spacemail, IMAP mail.spacemail.com:993, SSL)
E01 Inbox - Receive : IMAP trigger → Parse email → inbox.receive() → upload attachments to S3
                      → pg_notify('inbox_process', item_id)
E02 Inbox - Process : Postgres LISTEN inbox_process → Load item → (voice note? Amazon Transcribe,
                      poll every 10 s, max 36 checks) → Claude Sonnet 4.6 on Bedrock (JSON: patient
                      first/last/DOB, summary, chart_note) → inbox.complete()
                      any failure → inbox.complete(error) → status 'error'
Budibase "Orthea Inbox" app : list (/inbox) + message page (/item/:id)
```
- `inbox.receive(to, message_id, from_email, from_name, subject, body, attachments)` stores a message once (UNIQUE practice+message_id); sender not on `inbox.senders` → status `held` (never processed).
- `inbox.complete(item_id, transcript, summary, chart_note, first, last, dob, error)` → status `new`, stores `said_*` and `patient_*`; refuses items not in `processing`.
- Status values: `processing`, `new` (shown "To file"), `held`, `filed`, `dismissed`, `error` ("Needs a look").
- AWS requests are SigV4-signed in Code nodes (shared header in `src/sigv4.js`; test reproduces AWS's published example). Bedrock call needs headers `Authorization`, `X-Amz-Date`, `Content-Type`, and **`Accept: application/json`** (missing Accept → 400 "Accept Type invalid").
- Claude prompt treats the message as data (`<message>` tags), uses only what's stated, no clinical interpretation, returns JSON only.

## 4. Database (schema `inbox`, user `inbox_app`)
- `inbox.addresses(address PK, practice_id)` — `lso.inbox@ortheasecurity.com` → LSO.
- `inbox.senders(practice_id, email, display_name, active)` — approved senders. Current: `jstrick9@gmail.com`, `lso@ortheasecurity.com`. (Do not approve the inbox's own address.) `display_name` is what Inbox shows as "From" — set with
  `UPDATE inbox.senders SET display_name='Dr. Marc' WHERE email='jstrick9@gmail.com';`
- `inbox.items(id, practice_id, message_id, received_at, to_address, from_email, from_name, subject, body_text, attachments jsonb, status, transcript, summary, chart_note, said_first, said_last, said_dob, patient_first, patient_last, patient_dob, error, filed_by, filed_at, updated_at, patient_id/match [legacy, now NULL])`.
- Grants: `inbox_app` can EXECUTE `receive`/`complete`, SELECT items/senders/addresses, UPDATE only (status, chart_note, filed_by, filed_at, updated_at, patient_first, patient_last, patient_dob). After `04_island.sql` it has **no access to schema `consult`** (verified by test). It still reads `public.practice_users(email, practice_id, role, active)` to scope each signed-in user to their practice.
- Run SQL in Beekeeper on the **admin** connection, Auto Commit, and check each file ends with its `-- END OF …` line before Run All.

## 5. AWS and n8n setup
- S3 bucket `orthea-inbox` (us-east-2, private, SSE-S3). Keys: `transcripts/…` (Transcribe output), `<mailbox>/<hash>/<n>-<file>` (attachments).
- IAM user `orthea-inbox-n8n` (own policy: `bedrock:InvokeModel` for `us.anthropic.claude-sonnet-4-6`, `transcribe:Start/Get/DeleteTranscriptionJob`, S3 get/put/delete on `orthea-inbox/*`, list bucket). Separate from Consult's `orthea-n8n-bedrock` on purpose.
- Easypanel → n8n service → Environment: `INBOX_AWS_KEY`, `INBOX_AWS_SECRET` (no quotes/spaces; key ID must be **20 chars starting AKIA**, secret 40), optional `INBOX_BUCKET`. Redeploy n8n after changing. (A 23-character key ID once caused "security token invalid".)
- n8n credentials: **IMAP – LSO Inbox** (SSL/TLS on; host `mail.spacemail.com`, port 993, user = full address), **Postgres – Inbox (inbox_app)** (SSL **Require** — RDS rejects unencrypted connections: "no pg_hba.conf entry … no encryption").
- Publish E02 first, then E01. Successful runs are not saved (they contain patient data); failed ones are.
- Re-run a failed message: `UPDATE inbox.items SET status='processing', error=NULL WHERE id=N; SELECT pg_notify('inbox_process','N');`
- Transcribe formats handled: m4a, mp3, mp4, wav, flac, ogg/opus, amr, webm. `.caf` (iMessage) is stored but not transcribed — chart note says so.

## 6. Budibase app "Orthea Inbox" (Inbox DB = Postgres user `inbox_app`, SSL on)
Naming: queries `E · …`; components named as below (CSS targets the `data-name`s).
- **Queries on Inbox DB:** `E · Inbox list` (params email, view[new|filed|held|all]), `E · Inbox item` (id, email), `E · Set patient` (id, email, **firstName, lastName, dob**), `E · Save note` (id, email, chartNote), `E · File item` (id, email, chartNote; requires patient first+last), `E · Dismiss item` (id, email), `E · Reopen item` (id, email). `E · Inbox patients` is **deleted** (island change). Read queries: Function Read; the five writes: Function **Update**.
- **Navigation:** left, bg `#F7F3EE`, text `#1F1D1B`, hover bg `#E8E1D7` / text `#2F4A43`, active bg `#DCE7E4` / text `#2F4A43`, one link Inbox → `/inbox`; logo `https://orthea-assets.s3.us-east-2.amazonaws.com/orthea-inbox-160h.png`, height 30, hide title.
- **Screen `/inbox`** (home, Basic): New Embed (full `inbox-embed.html`); onLoad Update State `inboxView`=`new`; `Inbox Container` → `Inbox Header` (`Inbox Title`, `Inbox Tabs`: `Tab New/Filed/Held/All` — Secondary buttons, each onClick sets `inboxView` to `new`/`filed`/`held`/`all`, each with condition Update setting Variant=cta when `{{state.inboxView}}` equals its value); `Inbox List` data provider (query + email + view) → `Inbox Card` → `Inbox Columns` (header row texts Col When/From/Patient/Summary/Status) + `Inbox Repeater` → `Inbox Row` (onClick Navigate URL `/item/{{id}}`) with `Row When/From/Patient/Summary/Status` (status pill colours via Custom CSS conditions).
- **Screen `/item/:id`** (Basic): New Embed; `Item` data provider (`E · Inbox item`, id = `{{url.id}}`, email) → `Item Repeater` → `Item Container` → `Item Header` (`Item Back` Navigate `/inbox`, `Item Title`=summary, `Item Status`) / `Item Meta` ("From sender · received") / `Item Columns` → **`Note Card`** (`Note Card Title`; `Item Form` [Custom]: `Patient Row` with `Patient First/Last/DOB` text fields (fields firstName/lastName/dob, defaults from patient_first/last/dob), `Message Says` ("As written in the message: {{message_names}}", hidden when empty), `Chart Note` long-form, `Note Actions` [shown when status = new]: `Copy Note` (Copy To Clipboard + notification), `Save Note` (E · Set patient → E · Save note → refresh Item → notification), `File Note` (E · Set patient → E · File item → notification → Navigate `/inbox`; Disabled when firstName/lastName empty), `Dismiss Note` (E · Dismiss item with confirmation → Navigate `/inbox`); `Closed Box` [filed/dismissed] with `Closed Text` + `Reopen` (E · Reopen item → refresh); `Held Box` [held]; `Error Box` [error]) and **`Source Card`** (Subject, Attachments, Voice note/transcript, Email text; labels hidden when empty).
- Patient fields, Chart Note are disabled unless status = `new` (condition: Update setting Disabled, if status **Not equals** `new`).
- Hide/disable conditions that test "blank" should use operator **Is empty** (a blank reference value is saved as "nothing", so "Equals blank" never matches).
- Styling: `inbox-embed.html` = Consult shared shell + `inbox.css` (header row, list grid, cards, labels, `Note Actions` spacing, `Patient Row` grid). Paste the whole file into the screen's embed (hosted CSS from S3 does **not** load: Budibase's CSP allows only Budibase, Google Fonts, jsDelivr, rsms.me, Bootstrap CDN). Spacing rules must target `> div` of a named component (wrappers are `display: contents`).
- Brand: slate `#3E6A7A` (reversed `#A9CBD8`, icon tile `#2C4F5C`); Consult green `#446B63`, Voice terracotta `#A8603C`. Fraunces wordmark, italic descriptor after a hairline. Logos uploaded to the `orthea-assets` bucket.

## 7. Lessons / gotchas (save time)
1. **Budibase SQL parsing:** an apostrophe or `{{ }}` inside a `--` comment breaks parameter binding ("could not determine data type of parameter $1"). Keep comments free of both; run `node consult/budibase/check-sql.js <file.sql>`. Cast parameters `{{ x }}::text`.
2. A query's **column/binding list** is learned only when the query is **run, then saved** (clear Defaults afterwards and save again). A query's **parameter list** (what action boxes show) is edited by hand on the query page — stale action boxes = fix the Parameters list, not run.
3. Never click Run on Update queries; note that **Save/Save and Continue may execute the query once** — keep parameter Defaults blank so it matches nothing. Test with `inbox/tests/budibase.sh` instead.
4. Never leave test values in query Defaults (blank params would silently use them).
5. Budibase "Dev/Prod" banner does not protect Postgres data — Inbox DB is the real database.
6. Postgres via RDS needs SSL (n8n credential and Budibase datasource).
7. Don't put passwords/keys in chat (one `inbox_app` password was pasted earlier — **rotate it**: `ALTER ROLE inbox_app PASSWORD '…'` in Beekeeper, then update the n8n credential and the Budibase Inbox DB datasource).
8. Mail from `hello@spacemail.com` (welcome message) is correctly **held**.
9. Subject line is shown as sent; "From" uses the approved-sender `display_name`; patient column is the patient as named/confirmed (not a database match).

## 8. Status (end of 2026-10-12 session)
Done and working: database, E01/E02 (live; end-to-end test succeeded: Leo Marsh message → summary + chart note), Inbox list and message screens, tabs, header row, logo, styles, queries (tested), island change (DB) and queries, tests (DB 20, queries 23, n8n 30).

In progress (a Claude-in-Chrome session was doing the Budibase clicks; it stopped at several surprises — verify the end state in the builder): `/item/:id` island change — delete Patients provider + `E · Inbox patients` (done), Patient Picker/Match Note removed, `Patient Row` + three text fields (added), conditions on fields/Chart Note (Chart Note's was reversed; fix = Not equals `new`), `Message Says` text/condition, `E · Set patient` Parameters list changed to id/email/firstName/lastName/dob (saved), then **Save Note** and **File Note** action 1 bindings (id=URL id, email=Current User email, firstName/lastName/dob = Item Form fields), File Note disabled conditions (firstName/lastName Is empty), `New Embed` addition for `Patient Row` grid, Preview check, **then publish and Ctrl+F5**.

Known-to-verify from an earlier export review (some may already be fixed): `Dismiss Note`, `Reopen`, `Held Dismiss` Execute Query boxes must have `id` = URL id and `email` = Current User email; remove File-Note's condition copied onto `Dismiss Note`; `Tab Filed/Held/All` click value must be filed/held/all; `Reopen` button text; nav hover/active colours; the five write queries set to Function Update; "Do not display default notification" on action 1/2 of Save/File.

Pending small items: run the `display_name` UPDATE ("Dr. Marc") and make sure `E · Inbox list`/`E · Inbox item` use `COALESCE(NULLIF(s.display_name,''), NULLIF(i.from_name,''), i.from_email)` with the `inbox.senders s` LEFT JOIN; rotate `inbox_app` password.

## 9. Next steps (suggested)
1. Finish/verify the island change in Budibase, publish, run the checklist: open a message, edit patient fields, Save, File, Reopen, Dismiss, all four tabs, Back to Inbox.
2. Send fresh test emails (made-up patients; e.g. "Mia Torres, DOB 03/14/2015, referral from Dr. Kim Park") incl. one with a photo and one voice memo (iPhone Voice Memos → Share → Mail).
3. **E03 – attachments:** private bucket needs short-lived presigned links (n8n webhook, SigV4 presign) so the message page can show photo thumbnails and play audio.
4. Before real patient data: confirm BAAs/retention for every service, add check that sender really came from their mail provider (SPF/DKIM result) — From addresses can be forged.
5. Later: second practice (new alias + `inbox.addresses`/`inbox.senders` rows), optional shared patient directory, text-message intake (needs registered business number), a record-a-reply web page.

## 10. Working preferences (from the user)
- Give instructions **in the chat**, step by step, saying exactly where to click; do **not** create README/.md instruction files.
- Never publish Budibase/n8n changes unless asked; never push to a different branch; no PRs unless asked; commits end with the Co-Authored-By / Claude-Session lines.
- Approach LSO changes carefully; practice keys and passwords must not appear in chat or screenshots.
