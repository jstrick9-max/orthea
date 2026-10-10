# orthea.ai logos

Direction **B1** (chosen 2026-10-10): `orthea.ai` wordmark, a hairline, then the product in italic.
Typeface: Fraunces (SIL Open Font License) — roman opsz 144 / wght 500, italic opsz 72 / wght 400.
Text is converted to outlines, so the files need no fonts.

| Product | Accent | Reversed accent | Icon tile |
|---|---|---|---|
| Consult | `#446B63` | `#A9C7BE` | `#2F4A43` |
| Voice | `#A8603C` | `#E7B597` | `#8E4E2F` |

Ink `#1F1D1B`, cream `#F7F3EE`, hairline `#CFC6BA`.

`logos/`:
- `orthea-<product>.svg` / `-160h.png` (2×) / `-80h.png` — for light backgrounds
- `orthea-<product>-reversed.*` — for dark green or photos
- `<product>-icon-512.png`, `-180.png` — app icon, Apple touch icon
- `<product>-favicon-32.png`, `-16.png` — browser tab

Rebuild: download Fraunces from github.com/google/fonts (`ofl/fraunces`), then
`pip install fonttools uharfbuzz` and
`python3 brand/build_logos.py <fonts dir> brand/logos && node brand/render.cjs brand/logos`.
