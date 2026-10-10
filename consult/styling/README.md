# Consult — shared look (2026-10-10)

One stylesheet, `orthea-consult.css`, hosted next to the logos and pulled into every screen's embed.
It sets: fonts, cream page, one page edge, serif page titles, card-header style, field style,
buttons (primary clay / secondary white / quiet link / disabled), amber warning boxes, the
Dolphin tag, the nav hairline, the green user avatar, and hides the Budibase footer.
Screen embeds keep only their own layout rules; the shared rules are written to win over them.

Buttons are restyled on Patients, Archive, Intake and Add patient only — Review already styles
each of its buttons by name.

## Steps

1. **Upload** `orthea-consult.css` to the `orthea-assets` S3 bucket (same place as the logos,
   public read like them). Check
   https://orthea-assets.s3.us-east-2.amazonaws.com/orthea-consult.css opens as text.
2. **Each screen's embed** — Patients, Archive, Intake, Add patient, Review (**New Embed**): paste
   this as the very first line:
   ```html
   <style>@import url('https://orthea-assets.s3.us-east-2.amazonaws.com/orthea-consult.css?v=1');</style>
   ```
   When the file changes later: upload it again and change `?v=1` to `?v=2` in the five embeds
   (otherwise browsers keep the old copy for a while).
3. **Intake → Referrer Picker → Placeholder**: `Choose a referring dentist`.
4. **Data → `C · Patients for practice`**: replace the SQL with this folder's file, Save.
   Flags now show only while a consult is in review ("1 flag" / "3 flags"); an approved consult
   shows **Approved**.
5. **Patients → Row Status → Conditions**: in the first condition (amber pill) change the
   reference value `flags` to `flag`, so "1 flag" is amber too.
6. **Beekeeper (admin, Auto Commit)**: run `../dolphin-launch/04_blank_birthday.sql`. Dolphin sends
   12/30/1899 when a birthday is blank; this stores it as no birthday and clears the ones already
   saved (Teste Teste).
7. Publish.

## Check
- Every screen: title in the serif, content starts the same distance from the nav, no Budibase
  footer, green avatar bottom-left.
- Patients: "7 patients" beside the title; Archive is a quiet grey link; Justin Strickland (27788)
  shows **Approved**; Teste Teste has no DOB.
- Intake: both warnings are amber boxes; the dentist picker is full width; with no transcript
  and no notes **Save consult** is grey (if it stays clay, the Disabled condition isn't firing —
  tell me).
- Add patient: Cancel is a white button beside the clay Save patient.
- Review: unchanged apart from the page edge and title size.

`patients-additions.css` (earlier) is still needed on Patients: it holds the column widths.
