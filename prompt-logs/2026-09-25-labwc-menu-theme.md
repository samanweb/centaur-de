# Task log — Right-click (root) menu matches the desktop

**Date:** 2026-09-25
**Task:** "Make the right click menu (root menu) appearance match to the
desktop environment"

## Why it did not match

labwc draws the root menu, window menus, titlebars and window switcher itself.
GTK's stylesheet never reaches them. Centaur's `rc.xml` set only placement and
titlebar layout, and there was no `menu.xml`, so labwc showed its built-in
light theme and default menu.

## Changes

**Generated labwc themes.** `generate.py` writes `Centaur-<accent>-<palette>`
themes: 8 accents × 3 palettes = 24, installed in `/usr/share/themes`.
- Menus: `surface.overlay`, `border.default`, `text.primary`; the highlight is
  the accent mixed 20% over the overlay (new `color.mix`), because labwc
  wants solid colours.
- Titlebars match the GTK headerbar. The window switcher and snapping
  overlays use the accent.
- Every key was checked against labwc 0.20.2's `theme.c`. One key I had used,
  a close-button hover colour, does not exist in 0.20 and was dropped.
- A new contrast gate checks primary text on the menu highlight for every
  palette and accent: 117/117 checks pass.

**rc.xml** (`LabwcBackend`) now also:
- selects the theme for the resolved palette and accent, falling back to
  emerald, then to labwc's own look if nothing is installed;
- sets Inter from `font-ui` for titles (bold), menus and the switcher;
- sets `cornerRadius` 10 and drop shadows;
- turns menu icons off, because labwc draws icons in their own colours and
  symbolic icons would be near-black on a dark menu.

**menu.xml** (new):
- Root menu: Terminal (`lab-sensible-terminal`) · Change Background… ·
  Display Settings… · Lock Screen (Centaur's swaylock config, or the user's
  own) · Log Out (labwc Exit).
- Window menu: Minimize, Maximize, Fullscreen, Always on Top, Send to
  workspace, then Close set apart.
- An existing hand-written menu.xml is backed up once, like rc.xml.

**settingsd** re-applies the labwc config when `colour-mode`, `accent`,
`font-ui` or the sunrise/sunset times change, and on a timer at the 'auto'
palette boundary, since labwc cannot follow the time of day itself.

## Verified

- The real backend, with scratch settings (blue on dark), wrote valid XML
  (xmllint) selecting `Centaur-blue-dark`.
- A nested headless labwc 0.20.2 in debug mode read rc.xml, the
  Centaur-blue-dark themerc and menu.xml with no warnings or errors.
- A mock-up drawn from the generated values (not a screenshot: a headless
  labwc cannot be right-clicked) looked right in dark and light.
- Clean build, tests, and a staged install with 24 themes.

**Limits:** labwc menus have square corners (there is no setting), and the
menu has no icons (see above).

Version 0.1.9 → 0.1.10. No installer change was needed: the themes install
with meson, and the installer's session reload restarts settingsd, which
writes the new config and has labwc reconfigure.
