-- NEW Budibase query "C · Save composite" (Consult DB, Function: Update)
-- Parameters (all default blank): patientId, email, compositeUrl, removeComposite
-- compositeUrl    = the Letter Details form's Composite photo field: {{ form.compositeImage.url }}
-- removeComposite = the "Remove photo" checkbox ('true' to remove)
-- A new photo is saved only when it differs from the current one; the stored image is cleared
-- and n8n (C03 Consult - Fetch Composite) is notified to fetch the new file. Letters are
-- not regenerated — the photo is placed into the family letter when it's shown/downloaded.
-- Only while the latest consult is in 'review'.
WITH target AS (
  SELECT c.id FROM consult.consults c
   WHERE c.patient_id = CASE WHEN trim({{ patientId }}) ~ '^[0-9]+$'
                             THEN trim({{ patientId }})::bigint END
     AND c.practice_id IN (
           SELECT pu.practice_id FROM public.practice_users pu
            WHERE lower(pu.email) = lower({{ email }}) AND pu.active
         )
     AND c.status = 'review'
   ORDER BY c.created_at DESC
   LIMIT 1
),
inp AS (
  SELECT lower(trim(COALESCE({{ removeComposite }}, ''))) = 'true'   AS remove,
         NULLIF(NULLIF(trim({{ compositeUrl }}), ''), '``')            AS url
),
upd AS (
  UPDATE consult.consults c
     SET composite_url   = CASE WHEN inp.remove THEN NULL ELSE inp.url END,
         composite_image = NULL,
         updated_at      = now()
    FROM target t, inp
   WHERE c.id = t.id
     AND (   (inp.remove AND c.composite_url IS NOT NULL)
          OR (NOT inp.remove AND inp.url IS NOT NULL AND c.composite_url IS DISTINCT FROM inp.url))
  RETURNING c.id, c.composite_url
),
logged AS (
  INSERT INTO consult.audit_log (consult_id, action, actor)
  SELECT id::text, CASE WHEN composite_url IS NULL THEN 'removed composite photo' ELSE 'changed composite photo' END,
         lower({{ email }})
  FROM upd
)
SELECT u.id,
       CASE WHEN u.composite_url IS NOT NULL
            THEN (SELECT 'fetching' FROM (SELECT pg_notify('consult_composite', u.id::text)) n)
            ELSE 'removed' END AS result
FROM upd u;
