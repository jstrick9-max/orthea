# /review — letterhead in the Generated documents card

On-screen styling only. The Doctor and Family letters show the LSO letterhead (logo,
doctor list, rule) above the text and the address footer below it. The TMT summary is
an internal chart note and shows neither. Mirrors `letterhead/letterhead.html`.

What you're building, inside **Letter View**:

```
Letter View
├── Letterhead Top      ← new (Embed)
├── Doctor Letter Text
├── Family Letter Text
├── TMT Summary Text
└── Letterhead Footer   ← new (Embed)
```

Open the **Consult** app in the Budibase builder → **Design** → screen **/review**.

---

## Step 1 — Add the CSS

1. In the component tree (left panel), click **New Embed** — the first component under
   **Blank screen**, holding all the page's `<style>` blocks.
2. In the settings panel (right), click into the **Embed** box, go to the very end of
   the existing text (after the last `</style>`), add a new line.
3. Paste:

```html
<style>
/* ===== Letterhead (doctor + family letters) ===== */
@import url('https://fonts.googleapis.com/css2?family=Jost:wght@400;500&display=swap');
.lso-head, .lso-foot { max-width: 780px !important; font-family: 'Jost', 'Inter', sans-serif !important; color: #3D3836 !important; box-sizing: border-box !important; }
.lso-head { display: flex !important; flex-wrap: wrap !important; justify-content: space-between !important; align-items: flex-end !important; gap: 16px 24px !important; padding: 4px 0 20px !important; margin-bottom: 8px !important; border-bottom: 1px solid #D9D4D1 !important; }
.lso-logo { width: 190px !important; height: auto !important; display: block !important; }
.lso-doctors { text-align: right !important; font-size: 10px !important; line-height: 1.6 !important; letter-spacing: 0.06em !important; }
.lso-dr { font-weight: 500 !important; text-transform: uppercase !important; letter-spacing: 0.14em !important; }
.lso-cred { color: #8B8481 !important; }
.lso-note { color: #8B8481 !important; font-size: 9.5px !important; letter-spacing: 0.12em !important; text-transform: uppercase !important; margin-top: 4px !important; }
.lso-group + .lso-group { margin-top: 9px !important; }
.lso-foot { display: flex !important; flex-wrap: wrap !important; justify-content: center !important; align-items: center !important; gap: 6px 14px !important; margin-top: 16px !important; padding-top: 14px !important; border-top: 1px solid #D9D4D1 !important; font-size: 10px !important; letter-spacing: 0.24em !important; text-transform: uppercase !important; color: #8B8481 !important; }
.lso-foot b { font-weight: 500 !important; color: #3D3836 !important; }
.lso-dot { width: 3px !important; height: 3px !important; border-radius: 50% !important; background: #D9D4D1 !important; }
</style>
```

Nothing changes on screen yet.

## Step 2 — Add the footer

1. In the tree, expand **Documents Card → Documents Card Body** and click **Letter View**.
2. Click **+ Add component** (top of the tree) → **Embed**. It lands inside Letter View,
   at the bottom, below **TMT Summary Text** — exactly where the footer belongs.
3. Rename it **Letterhead Footer** (double-click its name in the tree, or **⋯ → Rename**).
4. In its **Embed** setting, paste:

```html
<div class="lso-foot">
  <span>553 Park Avenue</span><span class="lso-dot"></span>
  <span>New York, NY 10065</span><span class="lso-dot"></span>
  <span>Tel <b>212.755.2333</b></span>
</div>
```

The address line now appears under the letter.

## Step 3 — Add the header

1. Click **Letter View** again → **+ Add component** → **Embed**. It also lands at the
   bottom (below Letterhead Footer).
2. Move it to the top: drag it in the tree until it sits directly under **Letter View**,
   above **Doctor Letter Text** (or use **⋯ → Move up** until it's first).
3. Rename it **Letterhead Top**.
4. In its **Embed** setting, paste:

```html
<div class="lso-head">
  <img class="lso-logo" src="https://orthea-assets.s3.us-east-2.amazonaws.com/LSO-Letterhead-Logo.jpg" alt="Lemchen Salzer Orthodontics">
  <div class="lso-doctors">
    <div class="lso-group">
      <div><span class="lso-dr">Marc S. Lemchen</span> <span class="lso-cred">DMD</span></div>
      <div><span class="lso-dr">Jennifer Salzer</span> <span class="lso-cred">DDS</span></div>
      <div><span class="lso-dr">Andrew T. Lemchen</span> <span class="lso-cred">DMD</span></div>
      <div class="lso-note">Diplomates, American Board of Orthodontics</div>
    </div>
    <div class="lso-group">
      <div><span class="lso-dr">Bina Park</span> <span class="lso-cred">DDS</span></div>
    </div>
  </div>
</div>
```

The logo and doctor list now appear above the letter.

## Step 4 — Hide both on the TMT summary tab

Do this on **Letterhead Top**, then repeat on **Letterhead Footer**:

1. Select the component → at the bottom of the settings panel, click **Configure conditions**.
2. **Add condition**, and set it to read:
   **Hide component** · if `{{ State.reviewTab }}` · **Equals** · `tmt`
   (for the value, open the binding ⚡ picker → **State** → **reviewTab**).
3. **Save**.

No condition needed for edit mode — Letter View already hides itself when you click
**Edit letter**, and both Embeds are inside it.

## Step 5 — Test in Preview, then Publish

Open **Preview**, pick a patient with letters (e.g. Leo Marsh), and check:

| Do this | Expect |
|---|---|
| Doctor letter tab | Logo + doctors, thin rule, letter, thin rule + address |
| Family letter tab | Same letterhead |
| TMT summary tab | No logo, no address |
| Edit letter | Letterhead disappears with the letter |
| Cancel / Save changes | Letterhead comes back |

If it all checks out, **Publish** the Consult app.

## Optional — letter text in Jost

To match the printed letterhead font, add this line inside the `<style>` block from
Step 1 (just above `</style>`):

```css
[data-name="Doctor Letter Text"] p, [data-name="Family Letter Text"] p { font-family: 'Jost', 'Inter', sans-serif !important; }
```

---

Letterhead content is hardcoded to LSO. When Consult goes to a second practice, move the
logo URL, doctor list and address into `consult.practice_settings` and bind them here.
