-- Budibase query "C · Redeem launch" (Consult DB). Function: Read.
-- Parameters: code (default blank), email (default blank).
-- Swaps the one-time code from the Dolphin launch link for the patient. No row = code
-- expired, already used, or for another practice.
SELECT patient_id, patient_name, destination
FROM consult.redeem_launch({{ code }}, {{ email }});
