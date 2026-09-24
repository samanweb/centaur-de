# Task log — Create the design system

**Date:** 2026-09-24
**Task:** "Create design system inside the /design-system folder"
**Implements:** `architecture.md` §7
**Outcome:** Token source, generator, contrast audit, component specs, and 29 generated stylesheets.

## Context at start

- The folder had been renamed from `design system` to `design-system` and added
  to `claude.md`. Built into the hyphenated folder.
- **`screenshots/` was empty.** The four Base Center images and the topbar image
  were removed from disk earlier in the session. The palette was therefore
  reconstructed from reading those images while they were still present, not
  measured from files. Recorded in `design-system/README.md` under
  "Provenance and known gaps".

## What was built

```
design-system/
  tokens.json                 3 palettes, 8 accent ramps, scale tokens
  templates/components.css.in widget rules with {{token.path}} placeholders
  tools/generate.py           tokens -> GTK4 CSS, accent-map.json, preview.html
  tools/check_contrast.py     93 WCAG checks
  tools/color.py              shared colour maths, no dependencies
  components.md               widget specs: classes, states, tokens
  preview.html                generated swatch sheet
-> app/data/themes/           29 generated files, never hand-edited
```

## Key decisions

**Two token kinds, because GTK4 forces it.** Colours are emitted as
`@define-color` so `settingsd` can swap the accent block at runtime. Lengths are
substituted literally at build time, because GTK4 CSS has no length variable.
That split is the reason a generator exists rather than hand-written CSS.

**Load order is a contract:** accent block, then palette, then components.
`tokens-*.css` derives tints with `alpha(@centaur_accent_base, …)`, so it must
come after the accent block. All three go into one provider.

**Palettes name steps, not colours.** `accent-steps` maps `base`/`bright`/`dim`
onto a ramp, so adding a ninth accent needs no palette edits.

**Ink is resolved by the generator, never by the token file.** It picks whichever
of white or the ramp's dark ink actually contrasts against the resolved fill.

## The contrast audit changed the design

This is the part worth remembering. The first palette failed 4 of 93 checks —
light mode used accent step `600` with white ink, and emerald/cyan/amber/orange
fills landed between 3.19:1 and 3.77:1.

1. Made the generator choose ink by measured contrast instead of trusting the
   palette. 4 failures -> 2. Emerald 4.42:1, cyan 3.89:1 — still short.
2. Diagnosed the real cause: step `600` is mid-luminance, so *neither* white nor
   black reads on it. No ink choice can fix a fill that is too light to be dark
   and too dark to be light.
3. Added an `800` step to all 8 ramps and shifted light mode to `700/600/800`.
   93/93.

Light mode's accent fills are therefore darker than dark mode's by design. That
is a measured constraint; do not "correct" it back.

## Verification

```
python3 tools/generate.py --out ../app/data/themes --check   # up to date (29 files)
python3 tools/check_contrast.py                              # 93/93 passed
```

Both are intended as CI gates. `--check` fails if generated output is stale;
an unknown `{{token}}` in the template is a hard build error, so typos fail
rather than rendering as literal text.

Not verified: nothing has been rendered by GTK yet — `valac`, `meson` and
`gtk4-layer-shell` are still absent (`architecture.md` §12). The CSS is
syntactically GTK4-shaped but unproven against a real `GtkCssProvider`. First
Phase 0 task that touches GTK should load these stylesheets and confirm no
parse warnings.

## Accessibility rules encoded in components.md

- Focus ring is never removed; a widget that suppresses it draws its own.
- Status chips always carry a word — colour reinforces, never carries the message.
- `MeterRing` colour change is never the only signal of a problem.
- Workspace pill states survive a monochrome screenshot.
- `text.muted` is held to the 3.0 threshold because it is captions only.

## Open questions carried forward

- Icon theme: ship one or depend on Papirus? Cursor likewise (Bibata).
- `MeterRing` geometry is specified in prose but not enforceable from CSS —
  needs a unit test once `libcentaur-ui` exists.
- If the screenshots are restored, re-check `surface.window`, `surface.card` and
  the emerald ramp first.

## Next step

Phase 0 continues: install the toolchain, then the Meson skeleton and
`libcentaur-ui` consuming these tokens.
