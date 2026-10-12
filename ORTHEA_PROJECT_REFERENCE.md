# Orthea — project reference (Voice · Consult · Inbox)

As of 2026-10-12. Written to start a new Claude project/chat with full context. **Current focus: Orthea Inbox.**
Contains no passwords, keys or tokens. Never paste those into a chat; type them only into Beekeeper, Budibase, n8n, Easypanel and the AWS console.

---

## 0. How to work with me (owner's preferences — follow these)
- Owner: Justin (jstrick9@gmail.com), runs MME Consulting; builds and owns the Orthea products. First customer / design partner: **Lemchen-Salzer Orthodontics (LSO)**, Dr. Marc Lemchen; office manager **Romina Concha** (does the day-to-day filing in Dolphin/DDO).
- Give instructions **in the chat**, step by step, saying exactly **where** to click (which app, screen, component, setting). **Do not create README / .md instruction files.** (Exception: this reference file, requested explicitly.)
- **Never publish** Budibase apps or n8n workflows unless asked. Never push to a different git branch; **no pull requests** unless asked. Commit messages end with the Co-Authored-By + Claude-Session lines.
- Approach LSO carefully: installs on LSO PCs are avoided ("install nothing on the LSO PCs" for now); Dolphin changes are done by editing `dolphin.ini` only.
- **Orthea never writes to Dolphin.** Voice must never be blocked or touched by other products' work. **Do not touch Orthea Voice** unless explicitly asked.
- Practice keys, passwords and AWS keys must not appear in chat or screenshots. (An `inbox_app` DB password and a launch-key were shown in earlier sessions → **rotate both**.)
- When a mistake is mine, say so plainly. Report test results faithfully.

---

## 1. The three products at a glance

| | **Orthea Voice** | **Orthea Consult** | **Orthea Inbox** |
|---|---|---|---|
| Purpose | Doctor-voiced audio messages to patients (follow-ups, reminders) with a landing page, replies and attachments | Turns an orthodontist's shorthand consult notes (+ transcript) into a referring-dentist letter, a parent letter and an internal TMT summary, with conflict flags, doctor approval and PDF/Word downloads | Doctor-to-doctor messages (voice note/photo/text forwarded by email) become a transcribed, summarised chart note that staff review and file |
| Users | Practice staff send; patients listen/reply | Dr. Marc reviews/approves; staff create consults | Office staff (Romina) review and file notes |
| Maturity | **Live in production** (LSO and others); some hardening items outstanding | **Release 1 built and in LSO's hands**; Dolphin toolbar launch live on one LSO workstation; awaiting trial feedback + Dr. Marc's real letter rules | **Demo-grade, working end to end**; Budibase screens finishing; attachments viewer not built |
| Budibase app | "Orthea" (`/orthea`) | "Consult" (`/consult`) | "Orthea Inbox" (`/orthea-inbox`) |
| Prefix | Voice queries have no prefix; n8n `00`–`06` | Queries `C ·`; n8n `C01`–`C04` | Queries `E ·`; n8n `E01`–`E02` |
| DB user | `orthea_admin` (Voice datasource "PostgreSQL"; also the admin connection) | `consult_app` (datasource "Consult DB") | `inbox_app` (datasource "Inbox DB") |
| Schema | `public` | `consult` | `inbox` |
| Brand accent | terracotta `#A8603C` | green `#446B63` | slate `#3E6A7A` |

Common brand: **orthea.ai**, Fraunces wordmark + italic product name after a hairline; cream page `#F7F3EE`, ink `#1F1D1B`, pale-green card headers `#DCE7E4`, clay primary button `#B5653D`/`#C87D56`, Inter body font. Logos: repo `brand/logos/` (built by `brand/build_logos.py` + `brand/render.cjs`; uploaded to the public S3 bucket `orthea-assets`).

**Independence rule:** each product has its own Budibase app, DB user/schema and n8n workflows. They share the Budibase workspace, the Postgres instance, the n8n server, AWS account, and user logins (`public.practice_users`). Consult reads three `public` tables read-only (`practices`, `practice_users`, `doctors`). **Inbox reads only `public.practice_users`** and nothing of Consult (island change, see §5).

---

## 2. Shared infrastructure

- **Budibase** 3.37.1 self-hosted (Easypanel): `https://orthea-budibase.eqawdd.easypanel.host`. **One workspace only**; each product is a separate *app* in it. Apps: "Orthea" (Voice), "Consult", "Orthea Inbox". Datasources: "PostgreSQL" (Voice, `orthea_admin`), "Consult DB" (`consult_app`), "Inbox DB" (`inbox_app`), "Amazon S3". The Inbox DB datasource has **SSL on, rejectUnauthorized false** (copy the same setting for any new datasource).
- **Postgres** on AWS RDS (host `orthea-db.cf6cqiuq4300.us-east-2.rds.amazonaws.com`, db `orthea`). RDS **rejects unencrypted connections** — every client (Budibase datasource, n8n credential, Beekeeper) needs SSL.
- **Beekeeper Studio** connections: **"Orthea – Voice (admin)"** = `orthea_admin` (schema changes, admin work); "Orthea – Consult" = `consult_app` (day-to-day). Run migrations on the admin connection with **Auto Commit**; check that a pasted file ends with its `-- END OF …` line before Run All (large pastes have been truncated before).
- **n8n** 2.x (Easypanel): editor `https://orthea-n8n.ok5nlj.easypanel.host`; public webhooks served at `https://listen.ortheasecurity.com/webhook/…` (production URL) — Voice's patient pages, Consult's letter downloads and Dolphin launch use these.
- **AWS** (us-east-2, **BAA accepted**): Bedrock (Claude Sonnet 4.6, model id `us.anthropic.claude-sonnet-4-6`), S3, SES (Voice alert email), Transcribe (Inbox). IAM users per product: Voice (own), `orthea-n8n-bedrock` (Consult; env `CONSULT_BEDROCK_KEY/SECRET`), `orthea-inbox-n8n` (Inbox; env `INBOX_AWS_KEY/SECRET`, key ID must be exactly 20 chars). n8n's built-in AWS credential does **not** work for Bedrock (wrong signing scope) → every product signs SigV4 by hand in Code nodes and reads keys from container env vars set in Easypanel (redeploy n8n after changes).
- **Email** (Inbox): Spacemail, domain `ortheasecurity.com`; IMAP `mail.spacemail.com:993` SSL. Mailbox `lso.inbox@ortheasecurity.com` (alias-per-practice design: `<practice>.inbox@`).
- **ElevenLabs** (Voice only): text-to-speech with per-doctor `voice_id` and a pronunciation dictionary. (Plan/BAA status should be confirmed before any PHI flows there.)
- **Repo:** `jstrick9-max/orthea`, branch `claude/youthful-darwin-gt9zd7` (all work is committed there). Folders: `consult/` (everything Consult + the shared stylesheet in `consult/styling/`), `inbox/`, `brand/`, `letterhead/`. n8n workflow JSON exports, Budibase query SQL (`C · …sql`, `E · …sql`), tests and build scripts live next to each product.
- **Test rigs in the sandbox:** throwaway Postgres 16 at `/tmp/pgt`, port 5499 (restart: `rm -f /tmp/pgt/data/postmaster.pid; su postgres -c "pg_ctl -D /tmp/pgt/data -o '-p 5499 -k /tmp/pgt' -l /tmp/pgt/log -w start"`); suites: `consult/intake-review/tests/run.sh`, `consult/dolphin-launch/tests/run.sh`, `inbox/tests/run.sh` + `budibase.sh`, `node inbox/n8n/tests/run.mjs`. PowerShell 7 for the Dolphin launcher tests.

---

## 3. Orthea Voice (live; do not touch)

**What it is.** Practice staff create a message for a patient (type e.g. post-visit, reminder); an AI writes a script in the doctor's voice from a template; staff review/approve (or schedule); text-to-speech produces an MP3 in that doctor's cloned/selected voice; the patient gets an email/text link to a personal landing page with a player, attachments (documents, websites, videos), and quick reply options; replies alert staff by email routed per message type.

**Budibase app "Orthea"** (nav: Patients, New Message, Archive, Voices, Message Types, Reply Routing, Settings, Help). Screens `/patients` (metrics header: awaiting review, sent this week/month, avg turnaround, % listened; per-patient flyout with script edit, schedule presets, cancel schedule, archive, mark patient response resolved, attachments sent), `/new-message` (patient, voice, message type, notes, attachments, send by email/text), `/voices`, `/message-types`, `/reply-routing` (team members ↔ message types, coverage summary), `/archive`, `/settings`. Queries (24, datasource "PostgreSQL"): Scoped/Archived Submissions, Get Single Submission, Attachments for submission, Doctors for practice, Message types for practice, Resources for practice (+all), Reply routes for practice, Reply coverage, My Practice, metrics_header, create_submission, update_script, schedule_submission, cancel_schedule, attach_resources, insert_custom_resource, archive/unarchive/delete_patient, marked_handled, save/delete_reply_route.

**Data (schema `public`):** `practices`, `practice_users` (staff logins, per-practice), `doctors` (incl. `voice_id`, role Doctor/Coordinator), `submissions` (status flow `pending → approved/scheduled → sent`, plus `needs_voice`; script, audio_url, access_token, listened_at, sent_at…), `submission_responses`, `submission_resources`, `practice_resources`, `message_templates` (system/user prompt per message type, practice-specific or global), `reply_routes`, `pronunciation_rules`, `app_settings` (pronunciation dictionary ids).

**n8n (workflows `00`–`06`; exports of 00–03 seen):**
- `00 Scenario – Instant Script Generation (LISTEN/NOTIFY)` — Postgres trigger on channel `new_submission` → get template → build prompt → Claude (Bedrock) writes script → save to `submissions`.
- `01 … Backup (every 5 min)` — same pipeline on a schedule for anything missed.
- `02 Scenario – Generates Audio` — every 5 min: finds approved (or scheduled-and-due) submissions with no audio → doctor `voice_id` (missing → status `needs_voice`) → ElevenLabs TTS (pronunciation dictionary; "Invisalign" respelled for TTS) → MP3 to S3 → status `sent`, signed URL saved.
- `03 Scenario – Patient Landing Page` — webhooks under `listen/:token`: player page (fresh signed URL), `played` tracking, `respond` (saves reply, sends alert email via SES to the routed team member), resource redirects with open tracking, upload presign, video page.
- `04`–`06`: not exported into this work (likely sending/SMS/other) — **owner to supply if needed**.

**Status / known issues (Voice-side, not caused by Consult/Inbox):** an AWS access key and an ElevenLabs key were exposed in an earlier review → **rotate**; several older Voice queries don't scope by `practice_id` like newer ones; a couple of n8n nodes build SQL by string interpolation instead of parameters; a leftover debug `TestClick` row-click action + debug text on the Voice `/patients` screen **must be fixed before Voice is next published** (it breaks opening a patient). Voice's CSS conventions (Fraunces/Inter, cream/sage palette) are the template Consult/Inbox follow.

---

## 4. Orthea Consult (Release 1 built, LSO trial)

**Goal (Dr. Marc's own words, via two emails):** finish a consult, give his shorthand findings ("TMT notes") and walk away; staff confirm demographics; the system returns finished letters in his style needing only review/approval. **Order of authority:** (1) his TMT findings/plan always win, (2) Dolphin demographics, (3) consult transcript = supporting only, (4) AI never overrides. If the transcript contradicts his notes the system **flags it, uses his notes, and never silently resolves** (conflict detection is the most load-bearing requirement). Letter conventions: say "removal" not "extraction", "compliant" not "cooperative"; doctor letter opens "Hi [first name],", technical, never invents phases; family letter by first names, plain language; TMT summary is a chart note (no greeting/sign-off); sign-off "Thanks, / Best, / Marc S. Lemchen, DMD". His 3-release plan: R1 manual demographics + generate + approve; R2 Dolphin-connected; R3 near hands-off (do not build R3 first). Letter rules/prompts are stored per doctor in `consult.letter_rules` (editable without touching n8n); **they are placeholders until Dr. Marc's real ChatGPT instructions and approved sample letters arrive**.

**Budibase app "Consult"** (nav: Patients, Add patient [admin only], Archive; left nav, shared look). Screens: `/patients` (list; status pills: No consult / N flags / Review / Approved; row click → `/review/:id` if a consult exists else `/intake/:id`), `/intake/:id` (patient card with "Linked to Dolphin" tag, parent warning only when no parent first name, family & referring-dentist card with referrer picker incl. "add new", consultation card: doctor, consult date, type, transcript, TMT notes; photos card; fees card; **Save consult disabled until a transcript or TMT notes exist**), `/review/:id` (Generated documents card with Doctor/Family/TMT tabs, LSO letterhead + footer, edit letters, regenerate, Download PDF/Word once approved; inputs card with TMT/transcript, edit notes, "Input needed" form for consults saved empty; **Letter details** card: parents, family address, referring dentist + address, fees, composite photo; **Needs your review** flags card with check-off; Approve / Reopen gate), `/newpatient` (admin), `/archive`, `/launch/:t` and `/dolphin` (Dolphin entry screens, no UI). The patient id lives in the URL (`#/review/17`) so each browser tab has its own patient. Shared styling: one stylesheet pasted at the top of each screen's embed (`consult/styling/orthea-consult-embed.html`).

**Data (schema `consult`):** `consults` (tmt_notes, transcript, structured_record, conflicts, status draft→generating→review→approved, flags_reviewed, download_token, composite photo, fees, letter_slots…), `outputs` (draft/final text per output type), `patients` (name, DOB, dolphin_guid/dolphin_patient_id, parents, mailing_address, referring_doctor_id, archived_at), `referring_doctors`, `letter_rules`, `practice_settings` (consult_enabled, dolphin_linked), `launch_keys`, `launch_codes`, `audit_log`. Queries (28, datasource "Consult DB", prefix `C ·`).

**n8n workflows (all use credential "Postgres – Consult (consult_app)"; only Consult's own AWS keys):**
- `C01 Consult – Generate Documents` — Postgres LISTEN `consult_generate` (fires when status becomes `generating`) → load consult+rules → Bedrock: structured record → conflict check vs transcript → doctor letter → family letter → TMT summary → save outputs, status `review`.
- `C02 Consult – Download Letter` — public webhook `GET …/webhook/<id>/consult/letter/<token>/<doctor|family>/<pdf|docx>`; builds PDF/Word (letterhead embedded) in a Code node with no add-ons; token only valid while approved; logs the download.
- `C03 Consult – Fetch Composite` — LISTEN `consult_composite`; downloads the uploaded composite photo from Budibase, validates JPEG/PNG, stores base64 on the consult.
- `C04 Consult – Dolphin Launch` — webhook `POST …/webhook/consult/dolphin/launch` (launcher/.exe path; calls `consult.dolphin_launch`, returns a one-time link). The currently used "direct" Dolphin button does **not** need C04.

**Dolphin integration (the chosen "install nothing" version):** a line in each workstation's `dolphin.ini` `[Toolbar]` opens Chrome at `…/consult#/dolphin?g={PatientGUID}&i={PatientID}&f={PatientFirstName}&l={PatientLastName}&b={PatientBirthday}`; Budibase `/dolphin` calls `consult.dolphin_open()` (signed-in user → practice) which finds/creates the patient (GUID → Dolphin ID → name+DOB) and routes to Review/Intake. Name and DOB follow Dolphin on every click; parents/address/dentist/fees are never touched. Dolphin sends `12/30/1899` for a blank birthday → stored as no birthday. Address/parent tokens are not available in Dolphin 11.4 (tested); the address stays a staff field. A PowerShell launcher + later .exe exist as the future path (`consult/dolphin-launch/launcher/`). **Live on one LSO workstation; trial week, then other workstations.** Per-station `dolphin.ini` (CRLF, latin-1); remove the `OrtheaTest*` lines when done.

**Status:** Release 1 workflow complete and styled (generate, flags, approve/reopen, edit, regenerate, PDF/Word with letterhead, composite photo, letter-details card, Dolphin launch, admin-only Add patient). **Open:** Dr. Marc's real letter rules and sample letters; what TMT stands for; dictation option (record button/phone/Plaud/end-of-Zoom/typing); Dolphin's answer on third-party toolbar use / token list; roll-out to other PCs; a content pass on the doctor-letter prompt (it occasionally invents reasoning); the "+ Add new referring doctor" option in Letter Details doesn't create dentists (the Intake one does); archive rehearsal patients (Mary Ann Rehearsal, Liam O'Neil); revoke test launch keys; remove test lines from LSO's `dolphin.ini`. Possible later: Release 2/3 items, Patients-page search/filters/metric tiles.

---

## 5. Orthea Inbox (current focus)

**Origin:** Romina: doctors text each other voice notes/photos about shared patients; she emails them to herself and notes the chart in DDO. Inbox removes that: the doctor forwards to a practice address; Orthea stores, transcribes, summarises, drafts the chart note; Romina reviews, copies, files. Bigger idea (not built): doctor-to-doctor threads/voice replies via a phone-friendly web page, text-message intake (needs a registered business number), second practices (`bronsky.inbox@…`).

**Decisions:** completely separate product (own app, DB user `inbox_app`, schema `inbox`, workflows `E01/E02`, prefix **E**). **Island rule (2026-10-12):** Inbox does **not** read or match Consult patients; the patient is the name/birthday the message states (Claude extracts it), and staff correct first name, last name, DOB before filing. A shared patient directory is a possible future feature. Demo uses made-up patients/recordings only until every vendor in the chain is covered by a BAA (AWS is; confirm others).

**Flow:**
```
doctor email ─► lso.inbox@ortheasecurity.com (Spacemail IMAP)
E01 Inbox – Receive : IMAP trigger → Parse email → inbox.receive() [stores once; unknown sender → 'held']
                      → upload attachments to private S3 bucket → pg_notify('inbox_process', id)
E02 Inbox – Process : LISTEN inbox_process → load item → voice note? Amazon Transcribe (poll 10 s, ≤36×)
                      → Claude Sonnet 4.6 on Bedrock → {patient first/last/DOB, summary, chart_note}
                      → inbox.complete() → status 'new' ("To file"); any failure → status 'error'
Budibase "Orthea Inbox": /inbox list + /item/:id message page
```
Bedrock call needs headers `Authorization`, `X-Amz-Date`, `Content-Type` **and `Accept: application/json`**. Claude's prompt treats the email as data (`<message>` tags), uses only stated facts, returns JSON only. Transcribe formats: m4a, mp3, mp4, wav, flac, ogg/opus, amr, webm (`.caf` from iMessage is stored but not transcribed; the note says so). Successful executions aren't saved in n8n (they contain PHI); failed ones are. Re-run a failed message: `UPDATE inbox.items SET status='processing', error=NULL WHERE id=N; SELECT pg_notify('inbox_process','N');`

**Database (`inbox`):** `addresses(address → practice_id)`; `senders(practice_id, email, display_name, active)` (approved senders; unknown → held; **never approve the inbox's own address**; `display_name` is what the UI shows as "From", e.g. "Dr. Marc" for `jstrick9@gmail.com`; also `lso@ortheasecurity.com` = "LSO office"); `items(id, practice_id, message_id UNIQUE, received_at, to_address, from_email/name, subject, body_text, attachments jsonb, status [processing|new|held|filed|dismissed|error], transcript, summary, chart_note, said_first/last/dob, patient_first/last/dob, error, filed_by, filed_at, updated_at; legacy patient_id/match now NULL)`. Functions `inbox.receive(7 args)` and `inbox.complete(item_id, transcript, summary, chart_note, first, last, dob, error)` are SECURITY DEFINER with fixed search_path, executable by `inbox_app`. `inbox_app` can UPDATE only status, chart_note, filed_*, patient_first/last/dob, updated_at; after `04_island.sql` it has **no access to schema `consult`** (tested). Migration order: `00_inbox_role` (placeholder password → replace), `01_inbox`, `02_lso_setup` (edit sender emails first), `03_fix_setup` (used), `04_island`.

**AWS/n8n setup:** private S3 bucket `orthea-inbox` (us-east-2; keys `lso.inbox/<hash>/<n>-<file>` and `transcripts/…`); IAM user `orthea-inbox-n8n` with a policy limited to Claude invoke on the Sonnet 4.6 profile, Transcribe start/get/delete job, S3 object get/put/delete on the bucket, list bucket. n8n credentials: **IMAP – LSO Inbox**, **Postgres – Inbox (inbox_app)** (SSL Require). Publish E02 first, then E01 (E01 polls the mailbox about every minute). Optional env `INBOX_BUCKET`.

**Budibase app "Orthea Inbox"** (datasource "Inbox DB"; left nav, one link Inbox; logo `…/orthea-inbox-160h.png` height 30, hide title; nav colours: bg `#F7F3EE`, hover `#E8E1D7`/`#2F4A43`, active `#DCE7E4`/`#2F4A43`). Queries: `E · Inbox list` (email, view), `E · Inbox item` (id, email), `E · Set patient` (id, email, firstName, lastName, dob), `E · Save note` (id, email, chartNote), `E · File item` (id, email, chartNote; requires patient first+last), `E · Dismiss item`, `E · Reopen item` (id, email); `E · Inbox patients` is removed. Reads set Function Read; the five writes Function **Update**.
- `/inbox` (home): `Inbox Container` → `Inbox Header` (title + four tab buttons To file / Filed / Set aside / All that set state `inboxView` to new/filed/held/all; active tab becomes Action variant via condition) → data provider `Inbox List` → `Inbox Card` → `Inbox Columns` (header row: Received, From, Patient, Summary, Status) + `Inbox Repeater` → `Inbox Row` (click → `/item/{{id}}`) with Row When/From/Patient/Summary/Status pills.
- `/item/:id`: data provider `Item` (id=`{{url.id}}`) → `Item Repeater` → `Item Container` → `Item Header` (Back to Inbox, summary as title, status), `Item Meta` ("From <name> · <time>"), `Item Columns` → **Note Card** (`Item Form` Custom: `Patient Row` [Patient First/Last/DOB fields], `Message Says` ("As written in the message: …"), `Chart Note`, `Note Actions` [only when status = new]: Copy note (Copy To Clipboard), Save (Set patient → Save note), Mark as filed (Set patient → File item → back to inbox; disabled if first/last name empty), No note needed (Dismiss, confirm); `Closed Box` (Done by … on …, Reopen), `Held Box`, `Error Box`) and **Source Card** (subject, attachment names, voice-note transcript, email text; labels hidden when empty). Patient fields and Chart Note are disabled unless status = `new`.
- Styling: `inbox/budibase/inbox-embed.html` = Consult shared shell + `inbox.css` (header row, grid rows, cards, grey field labels, spacing for `Note Actions`, `Patient Row` grid). Paste the whole file into each Inbox screen's embed (+ the `Patient Row` snippet).

**Status (2026-10-12):** database ✅, n8n E01/E02 ✅ live and tested end to end (Leo Marsh test → correct summary and note), Budibase `/inbox` ✅ working (tabs, header, pills), message page ✅ working in its first version, logo ✅, queries and workflows tested in sandbox (DB 20 + queries 23 + n8n 30 checks) ✅. **In progress:** converting `/item/:id` to the island version (Patients provider and picker removed; Patient Row text fields, conditions, Save/File actions' parameters `firstName/lastName/dob`, `Message Says` text) — a Claude-in-Chrome session was doing the clicks and stopped at several points; **verify the end state in the fresh export** (see checklist below), then publish and hard-reload (Ctrl+F5).

**Verification checklist for the new chat (compare against the fresh Budibase export):**
1. `E · Inbox item`/`E · Inbox list` SQL contain no `consult` and have `patient_first/patient_last/patient_dob` (item) / `patient_label` (list); Defaults blank; `E · Set patient` Parameters = id, email, firstName, lastName, dob; the five write queries are Function Update.
2. `/item/:id`: no `Patients` data provider; Patient Picker/Match Note gone; Patient First/Last/DOB present with defaults from `patient_first/last/dob`; the three fields and Chart Note disabled when `status` **Not equals** `new`; Save Note and File Note action 1 pass id=`{{url.id}}`, email=user email, firstName/lastName/dob from `Item Form`; File Note disabled when firstName/lastName **Is empty**; Dismiss Note has no copied condition and its query has id+email; Reopen and Held Dismiss queries have id+email; Reopen button text correct.
3. `/inbox`: each tab's Update State value matches its tab (new/filed/held/all); header row embed present.
4. Both screens' embeds contain the full `inbox-embed.html` and the `Patient Row` snippet; nav colours as above.
5. `inbox_app` has no access to `consult` (run the final SELECT of `04_island.sql`: false/false).
6. Display name: `UPDATE inbox.senders SET display_name='Dr. Marc' WHERE email='jstrick9@gmail.com';` and both queries use `COALESCE(NULLIF(s.display_name,''), NULLIF(i.from_name,''), i.from_email)` with `LEFT JOIN inbox.senders s …`.

**Test emails used (made-up):** from `jstrick9@gmail.com` to `lso.inbox@ortheasecurity.com` — "Leo Marsh (DOB 08/27/2013) extraction done" (Dr. Neugarten, oral surgeon), "Owen Hale impacted canine", "Ava Reyes … no birthday", "New referral – Mia Torres (DOB 03/14/2015) from Dr. Kim Park, Park Family Dentistry". Voice-memo test: iPhone Voice Memos → Share → Mail.

**Next (suggested order):** finish/verify the island screen; publish; fresh tests (photo + voice memo); **E03 attachments viewer** (private bucket ⇒ n8n webhook returning short-lived presigned links for photo thumbnails and audio playback on the message page); before real PHI: BAAs/retention for all vendors, check SPF/DKIM so a forged From can't pass the approved-sender list, remove the old exposed credentials; then second practice setup, optional shared patient directory, text intake, record-a-reply page.

---

## 6. Conventions and hard-won lessons (apply to every product)

**Budibase**
1. `[data-name="X"]` is a `display: contents` wrapper: styles that paint or space (background, border, padding, **margin**, grid) must target `[data-name="X"] > div`; font/colour rules on nested `p` work directly. Use `:is(...)`, doubled attribute selectors or `!important` to beat Budibase defaults.
2. **Hosted CSS from S3/other sites does not load** (Budibase CSP allows only itself, Google Fonts, jsDelivr, rsms.me, Bootstrap CDN) → paste CSS inline in an Embed per screen.
3. **SQL parsing quirk:** an apostrophe or `{{ }}` inside a `--` comment breaks parameter binding ("could not determine data type of parameter $1"). Keep comments free of both; cast parameters `{{ x }}::text`; Budibase sends blanks untyped. Checker: `node consult/budibase/check-sql.js file.sql`.
4. A query's **column/binding list** is learned only when it is **Run then Saved** (use temporary Defaults, run, save, clear Defaults, save again). A query's **parameter list** (the boxes in action editors) is edited by hand on the query page. **Never leave test values in Defaults** (a blank binding silently uses them).
5. Never click Run on Update queries; **"Save and Continue" can execute a query once** — keep its parameter Defaults blank so it matches nothing. The Dev/Prod banner does **not** protect Postgres data.
6. Conditions that test blank: use operator **Is empty** (a blank reference value is stored as nothing, so "Equals blank" never matches). Duplicating a component copies its actions/conditions unchanged — edit each copy. Continue-if/Stop-if does not reliably halt an action chain.
7. Budibase buttons can't make arbitrary authenticated HTTP calls → pattern: button flips a status via Execute Query, Postgres `pg_notify` wakes an n8n Postgres-LISTEN trigger.
8. State shared with **Persist** is shared across browser tabs → keep the patient/message id in the URL (`/review/:id`); `{{ url.x }}` only includes route params, not `?query`; Budibase JS runs in a sandboxed frame → use `window.top.location.hash`; unmatched routes fall back to the home screen.
9. Navigate/ordering: set up data providers before the screens that use them; hide-if/disable-if rely on a data provider's row fields only after the query's columns are learned.
10. The builder export (`db.txt`) is JSON lines of documents; screens are `screen_…` docs with a `props._children` tree, queries `query_…` docs with `fields.sql`, `parameters`, `schema`; datasources `datasource_…`; apps `workspace_app_…`. Useful for auditing a build against the instructions.

**n8n**
1. Code nodes have no `URL` class; plain `require('crypto')` works; Bedrock/Transcribe/S3 are signed by hand (SigV4 helper in `inbox/n8n/src/sigv4.js`, verified against AWS's published test vector).
2. A multi-line `queryReplacement` expression breaks parameters → compute values in a Set/Code node and pass a one-line array.
3. Postgres Trigger (LISTEN) workflows have no public URL; webhook workflows use the production URL (`listen.ortheasecurity.com`).
4. n8n credential creation: Overview → Credentials → Create credential (or from a node's credential dropdown). IMAP needs SSL/TLS on or the server offers no auth method ("No supported authentication method(s)"). Postgres needs SSL "Require".
5. n8n workflow files are generated for Inbox by `inbox/n8n/build.mjs` from `src/*.js`; edit sources, rebuild, run `tests/run.mjs`, import the JSON.

**Postgres**
SECURITY DEFINER functions with `SET search_path`, `REVOKE … FROM PUBLIC`, column-level UPDATE grants, hashed keys/codes, `unique_violation` handling; migrations are idempotent (`IF NOT EXISTS`, `CREATE OR REPLACE`, `DROP FUNCTION IF EXISTS`). Multi-practice scoping everywhere: every query resolves the signed-in user's practice via `public.practice_users(email, active)`.

**AWS/IAM:** one IAM user and policy per product; env vars set in Easypanel (no quotes/spaces), redeploy n8n; diagnose key problems by printing only lengths/first 4 chars (a 23-char key ID caused "security token invalid").

---

## 7. Outstanding items across the portfolio
- **Security:** rotate exposed AWS + ElevenLabs keys (Voice), the `inbox_app` password and any LSO launch keys shown in screenshots; unscoped older Voice queries; interpolated SQL in some Voice n8n nodes; Voice `TestClick` debug leftover (fix before next Voice publish); sender-authenticity check for Inbox.
- **Consult:** items in §4 "Open"; Dolphin permission/trial; roll-out; real letter rules.
- **Inbox:** items in §5 "Next" and the verification checklist.
- **Business:** pricing/packaging (Consult sold standalone or with Voice; Inbox likewise), Weave/Spruce/Doximity overlap for doctor-to-doctor messaging, BAAs for every vendor before real PHI.
