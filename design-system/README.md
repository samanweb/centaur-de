# Centaur DE — Design System

Single source of truth for how Centaur looks. Implements [`../architecture.md`](../architecture.md) §7.

**The rule this exists to enforce:** no widget in `libcentaur-ui`, no module, and
no stylesheet fragment may contain a literal colour or a literal length. Both
come from `tokens.json`.

---

## Why a generator rather than hand-written CSS

The Appearance page offers three colour modes and eight accent colours. That is
24 combinations, and they must stay consistent as the system grows. Writing
those by hand guarantees drift.

GTK4 also treats the two kinds of token differently, which forces the split:

| Token kind | Mechanism | When it resolves |
|---|---|---|
| Colours | `@define-color` | **Runtime.** `centaur-settingsd` redefines the accent block and reloads the `CssProvider`; changing accent is a few milliseconds, not a restart. |
| Lengths — spacing, radii, font sizes | literal substitution | **Build time.** GTK4 CSS has no variable mechanism for lengths, so the generator substitutes them into the component rules. |

---

## Files

```
design-system/
  tokens.json                 source of truth — edit this
  templates/
    components.css.in         widget rules, with {{token.path}} placeholders
  tools/
    generate.py               tokens.json + template -> GTK4 CSS
    check_contrast.py         WCAG audit; run in CI
    color.py                  shared colour maths, no dependencies
  components.md               widget specs: classes, states, tokens
  preview.html                generated swatch sheet for review
```

Generated output lands in `../app/data/themes/` and is never edited by hand:

```
app/data/themes/
  tokens-dark.css  tokens-pure-dark.css  tokens-light.css
  accents/<accent>-<palette>.css          24 files
  components.css
  accent-map.json                         read by centaur-settingsd
```

---

## Usage

```sh
tools/generate.py --out ../app/data/themes --preview preview.html
tools/generate.py --out ../app/data/themes --check    # CI: fails if stale
tools/check_contrast.py                               # CI: fails on regression
```

---

## Load order is a contract

Stylesheets must be loaded in this order, because `@define-color` resolves in
the order it is seen:

1. `accents/<accent>-<palette>.css` — defines `centaur_accent_*`
2. `tokens-<palette>.css` — defines everything else, and derives the tints
   (`centaur_accent_bg` is `alpha(@centaur_accent_base, …)`, so it needs step 1)
3. `components.css` — the rules

All three go into one `Gtk.CssProvider` at `STYLE_PROVIDER_PRIORITY_APPLICATION`.

At runtime `centaur-settingsd` regenerates **only** step 1 — five
`@define-color` lines it builds from `accent-map.json` — and reloads the
provider.

---

## Modes

| Mode | Palette | Notes |
|---|---|---|
| `dark` | `dark` | Default. Dark blue-black surfaces. |
| `pure-dark` | `pure-dark` | OLED blackout; window background is true `#000000`. |
| `light` | `light` | Daylight contrast. |
| `auto` | — | Not a palette. `settingsd` resolves it to `dark` or `light` on the sunrise/sunset schedule. Never emitted as its own stylesheet. |

---

## Accents

Eight ramps — emerald (default), blue, cyan, purple, amber, orange, slate,
crimson — each with steps `300 … 800` plus a dark `ink`.

A palette does not name colours; it names **steps**:

```json
"accent-steps": { "base": "400", "bright": "300", "dim": "600", "ink": "auto" }
```

Dark modes take `400` as the fill. Light mode takes `700`, because a mid-tone
fill cannot carry readable text in either direction — that is a measured
constraint, not a preference (see below).

`ink` is resolved by the generator, never by the token file: it picks whichever
of white or the ramp's dark ink actually contrasts against the resolved fill.

---

## Contrast is enforced, not intended

`check_contrast.py` runs 93 checks: every text token against every surface it
may sit on, every accent's ink against its own fill, and every accent used as
text on a card.

Thresholds are WCAG 2.1 — 4.5:1 for body text, 3.0:1 for large text and UI
boundaries. `text.muted` is held to 3.0 because it is only ever used for
captions repeating information available elsewhere; `text.disabled` is excluded
as decorative.

**This audit already changed the design.** Light mode originally used step `600`
with white ink; emerald and cyan landed at 4.42:1 and 3.89:1. Adding an `800`
step and shifting light mode to `700/600/800` fixed it. Any future palette edit
must keep the suite at 93/93.

---

## Adding a token

1. Add it to `tokens.json` — under `scale` for a length, under every palette for
   a colour. **A colour added to one palette must be added to all three.**
2. Reference it in `templates/components.css.in`:
   - colour → `@centaur_<group>_<name>` (dots and dashes become underscores)
   - length → `{{group.name}}`
3. Run `tools/generate.py`. An unknown `{{…}}` is a hard error, so typos fail the
   build rather than rendering as literal text.
4. Run `tools/check_contrast.py` if you touched a colour.
5. Document the widget use in `components.md`.

---

## Provenance and known gaps

The palette was reconstructed from the four Base Center reference screenshots
and the topbar image. **Those files were removed from `screenshots/` during the
session that produced this system**, so the hex values are a reading of those
images rather than a measurement of them.

Treat them as a calibrated starting point. If the originals are restored, the
values worth re-checking first are `surface.window`, `surface.card` and the
emerald ramp — everything else is derived structure that holds regardless.

Two things this system deliberately does not yet cover:

- **Icon theme.** The screenshots referenced Papirus-Dark and Bibata cursors.
  Whether Centaur ships its own icon set or depends on one is unresolved.
- **`MeterRing` arc geometry.** The tokens give it colours; stroke width, cap
  style and sweep are drawing code in `libcentaur-ui`, specified in
  `components.md` but not enforceable from CSS.
