# Orthea Inbox (demo build)

Doctors forward a voice note, photo or text to their practice's inbox address; Orthea transcribes
it, finds the patient, drafts a chart note, and staff copy the note into the chart.
Orthea never writes to Dolphin.

```
doctor's phone ─email─▶ lso.inbox@ortheasecurity.com (Spacemail)
     n8n I01 (IMAP) ─▶ inbox.receive()  → stored once; unknown senders held
                    ─▶ attachments to S3, transcribe, AI: patient + summary + chart note
                    ─▶ inbox.complete() → patient matched (name+DOB, name, last+DOB)
Budibase  Inbox screen ─▶ check patient, Copy note, Filed / Dismiss
```

## A separate product

| Layer | Inbox | Shared with Consult / Voice |
|---|---|---|
| Budibase | its own app **Orthea Inbox** (own screens, nav, URL, roles) | the workspace and user logins |
| Budibase data source | its own **Inbox DB**, signed in as `inbox_app` | — |
| Postgres | its own schema `inbox`, own user `inbox_app` | reads `consult.patients` (id, name, DOB, Dolphin ID only) and `public.practice_users` to scope by practice |
| n8n | its own workflows `I01 …`, own Postgres credential (`inbox_app`) | the n8n instance, S3 and AI credentials |
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
| 2 | n8n I01 workflow | next |
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
