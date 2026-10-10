-- Budibase query "C · Dolphin open" (Consult DB). Function: Read.
-- Parameters (default blank): email, guid, dolphinId, firstName, lastName, birthday.
-- Finds or creates the Dolphin patient for the signed-in user’s practice.
-- No patient_id = refused; reason says why.
SELECT patient_id, patient_name, destination, outcome, reason
FROM consult.dolphin_open({{ email }}, {{ guid }}, {{ dolphinId }}, {{ firstName }}, {{ lastName }}, {{ birthday }});
