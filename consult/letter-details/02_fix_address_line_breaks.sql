-- One-time cleanup (Beekeeper, Consult connection): addresses already saved with a literal "\n"
-- get real line breaks, and stray spaces around the breaks are removed.
UPDATE consult.patients
   SET mailing_address = trim(regexp_replace(replace(mailing_address, '\n', E'\n'), '[ \t]*\n[ \t]*', E'\n', 'g'))
 WHERE mailing_address LIKE '%\\n%';

UPDATE consult.referring_doctors
   SET mailing_address = trim(regexp_replace(replace(mailing_address, '\n', E'\n'), '[ \t]*\n[ \t]*', E'\n', 'g'))
 WHERE mailing_address LIKE '%\\n%';
