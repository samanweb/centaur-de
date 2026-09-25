# Task log — Desktop wallpaper tool

**Date:** 2026-09-24
**Task:** "add a tool to apply and change background images to the desktop
properly, update changes to installer."

## Before

`org.centaur.appearance wallpaper` existed but nothing read it. The
`centaur-bg` module was planned in architecture.md and never built. Nothing
drew a desktop background at all.

## Built

**`centaur-bg`** (`app/daemons/bg/`, libexec, headless, no GTK) is started by
centaur-session before settingsd and the topbar. It turns three keys into a
swaybg command line:
- `wallpaper`: a path; empty or missing falls back to the default;
- `wallpaper-mode`: fill, fit, stretch, center, tile or solid (new key);
- `background-color`: `#rrggbb` (new key).

How it runs swaybg:
- On a change it starts the new swaybg, then stops the old one 500 ms later,
  so there is no flash. Bursts of key changes are coalesced into one restart.
- A swaybg that dies on its own is respawned after 1, 2 and 4 s, then left
  off. Children get `PR_SET_PDEATHSIG`, so a killed centaur-bg never orphans
  one.
- The flags, mode names and colour format were checked against swaybg's
  `main.c`.
- This settles architecture.md's open question: it stays a separate, tiny
  process.

**`centaur-background`** is the "Background" window in the launcher.
- A preview in the first monitor's shape, with the background colour painted
  underneath exactly as swaybg shows it.
- Position dropdown and colour button.
- A wallpaper grid from `/usr/share/backgrounds/centaur`,
  `~/.local/share/backgrounds` and the system `backgrounds`/`wallpapers`
  folders, three levels deep so KDE packages work too. Thumbnails decode one
  at a time at reduced size.
- Add Picture… copies the picture into `~/.local/share/backgrounds`; Remove
  works only on added pictures and falls back to the default if the removed
  picture was in use.
- Picking a picture while in solid-colour mode switches back to fill.
- Changes apply immediately; there is no Apply button.

**Wallpapers:** six token-generated SVGs (emerald, blue, purple and amber
dark; emerald and blue light) from `generate.py`, checked for staleness with
the rest (36 files). All decode through gdk-pixbuf, the loader swaybg uses.
Shared lookup is in `lib/core/wallpaper.vala`.

## Styling bugs found by rendering the windows

Offscreen renders of Background and Displays showed light, unreadable title
bars, and white buttons and dropdowns with pale text. GTK's built-in theme
paints buttons and the switch knob with a `background-image` gradient in
every state, over the design system's `background-color`, so no button colour
had ever been visible. This probably affected the topbar's menu buttons too.

Fix, in the design system:
- reset `background-image`, `box-shadow` and `text-shadow` on buttons in all
  states, and on the switch knob;
- style `headerbar` and the window controls from the tokens;
- give a disabled accent button a muted look;
- `Ui.Theme` sets `gtk-application-prefer-dark-theme` from the resolved
  palette, so unstyled widgets follow it.

Re-renders confirmed the fix.

## Verified

- **centaur-bg with a stand-in swaybg:** startup command, wallpaper change,
  fit + colour (one restart), solid, missing file → default, the handover
  order (new starts before old stops), crash respawn, clean stop, and no
  orphan after SIGKILL.
- **The Background window on a nested headless labwc:** 7 tiles with 7
  thumbnails, current wallpaper preselected, clicking sets the key and leaves
  solid mode, Remove deletes and resets to the default.
- Clean build, staged install, strict schema compile, both `.desktop` files
  validate, 93/93 contrast.

**Not tested:** real swaybg drawing, since it is not installed yet; the
installer installs it.

## Installer / packaging

- New wallpaper step installs swaybg with the package manager
  (`--no-wallpaper` skips it); `--check` reports it.
- On reinstall, centaur-bg is restarted with the others. A session started
  by an older centaur-session gets centaur-bg started for it, so the
  wallpaper appears without logging out.
- PKGBUILD depends on `swaybg`. The pacman message and uninstaller explain
  where wallpapers and added pictures live.
- Version 0.1.6 → 0.1.7.
