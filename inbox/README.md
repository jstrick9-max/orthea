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

**Demo rule: made-up patients and recordings only** until BAAs are signed with the
transcription and AI providers.

| Step | What | Status |
|---|---|---|
| 1 | Database: `01_inbox.sql`, `02_lso_setup.sql` | built, tested (`tests/run.sh`, 19 checks) |
| 2 | n8n I01 workflow | next |
| 3 | Budibase Inbox screen | after 2 |
| 4 | Demo recordings | after 3 |

## Step 1 — database (Beekeeper, admin connection, Auto Commit)

1. Run `01_inbox.sql`. The last result shows 3 tables and 2 functions.
2. Open `02_lso_setup.sql`, replace `YOUR.EMAIL@example.com` with the address(es) you'll send
   test notes from (one line each), then run it. Only these senders are processed; anything
   else sent to the inbox is held.

Matching only ever looks at the practice the inbox address belongs to. Two patients with the
same name and no birthday in the message are left for staff to pick.
