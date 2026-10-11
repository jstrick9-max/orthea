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
| 3 | Budibase app **Orthea Inbox** + data source **Inbox DB** | after 2 |
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
