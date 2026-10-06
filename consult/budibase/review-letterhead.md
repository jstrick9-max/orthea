# /review — letterhead in the Generated documents card

On-screen styling only. The Doctor and Family letters show the LSO letterhead (logo,
doctor list, rule) above the text and the address footer below it. The TMT summary is
an internal chart note and shows neither. Mirrors `letterhead/letterhead.html`.

Logo: `https://orthea-assets.s3.us-east-2.amazonaws.com/LSO-Letterhead-Logo.jpg`

## 1. Letterhead Top (Embed)

Inside **Letter View**, add an **Embed** as the *first* child (above Doctor Letter Text).
Name it `Letterhead Top`. Embed:

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

## 2. Letterhead Footer (Embed)

Inside **Letter View**, add an **Embed** as the *last* child (below TMT Summary Text).
Name it `Letterhead Footer`. Embed:

```html
<div class="lso-foot">
  <span>553 Park Avenue</span><span class="lso-dot"></span>
  <span>New York, NY 10065</span><span class="lso-dot"></span>
  <span>Tel <b>212.755.2333</b></span>
</div>
```

## 3. Conditions (both Embeds)

On **Letterhead Top** and **Letterhead Footer**, add one condition:

- **Hide component** — `{{ State.reviewTab }}` **Equals** `tmt`

Edit mode needs no condition: Letter View already hides when `editMode` = `yes`, and the
Embeds are inside it.

## 4. CSS

Paste at the end of the screen's existing style **Embed** (the first component on the
screen, `New Embed`), as its own `<style>` block:

```html
<style>
/* ===== Letterhead (doctor + family letters) ===== */
@import url('https://fonts.googleapis.com/css2?family=Jost:wght@400;500&display=swap');

.lso-head, .lso-foot {
  max-width: 780px !important;
  font-family: 'Jost', 'Inter', sans-serif !important;
  color: #3D3836 !important;
  box-sizing: border-box !important;
}
.lso-head {
  display: flex !important;
  flex-wrap: wrap !important;
  justify-content: space-between !important;
  align-items: flex-end !important;
  gap: 16px 24px !important;
  padding: 4px 0 20px !important;
  margin-bottom: 8px !important;
  border-bottom: 1px solid #D9D4D1 !important;
}
.lso-logo {
  width: 190px !important;
  height: auto !important;
  display: block !important;
}
.lso-doctors {
  text-align: right !important;
  font-size: 10px !important;
  line-height: 1.6 !important;
  letter-spacing: 0.06em !important;
}
.lso-dr {
  font-weight: 500 !important;
  text-transform: uppercase !important;
  letter-spacing: 0.14em !important;
}
.lso-cred { color: #8B8481 !important; }
.lso-note {
  color: #8B8481 !important;
  font-size: 9.5px !important;
  letter-spacing: 0.12em !important;
  text-transform: uppercase !important;
  margin-top: 4px !important;
}
.lso-group + .lso-group { margin-top: 9px !important; }

.lso-foot {
  display: flex !important;
  flex-wrap: wrap !important;
  justify-content: center !important;
  align-items: center !important;
  gap: 6px 14px !important;
  margin-top: 16px !important;
  padding-top: 14px !important;
  border-top: 1px solid #D9D4D1 !important;
  font-size: 10px !important;
  letter-spacing: 0.24em !important;
  text-transform: uppercase !important;
  color: #8B8481 !important;
}
.lso-foot b { font-weight: 500 !important; color: #3D3836 !important; }
.lso-dot {
  width: 3px !important;
  height: 3px !important;
  border-radius: 50% !important;
  background: #D9D4D1 !important;
}
</style>
```

## 5. Optional — letter text in Jost

To match the printed letterhead, add inside the same `<style>` block:

```css
[data-name="Doctor Letter Text"] p,
[data-name="Family Letter Text"] p {
  font-family: 'Jost', 'Inter', sans-serif !important;
}
```

## Check

- Doctor letter / Family letter: logo + doctors above, rule, letter, rule + address.
- TMT summary: no letterhead.
- Edit letter: letterhead disappears with the letter; returns on Cancel/Save.
- Approved state: unchanged (letterhead stays, edit buttons hidden as before).

Letterhead content is hardcoded to LSO. When Consult goes to a second practice, move the
logo URL, doctor list and address into `consult.practice_settings` and bind them here.
