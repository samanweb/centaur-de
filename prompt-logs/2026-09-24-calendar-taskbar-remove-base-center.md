# Task log — Calendar, taskbar, and removing Base Center

**Date:** 2026-09-24
**Task:** "When user click date time in the top bar calendar must need to drop
out, when application open the application icon must display in the top bar
until application close. remove the base center from project completely."
**Outcome:** All three done. Clean build from an empty build directory, both
design-system gates pass, the stylesheet parses in GTK with no errors, and the
window tracker was probed against the live labwc session (it reported the open
window with the right app id and focus state). The bar itself has not been seen
running: a second `centaur-topbar` hands off to the one already in the session.

## Calendar

`ClockIndicator` is now a `GtkMenuButton` (same pattern as launcher and power)
whose popover holds a full-date heading and a `GtkCalendar`. Built on first
open through `set_create_popup_func`, and reset to today on every `show`.
`select_day` is deprecated in GTK 4.20, but its replacement does not exist in
4.12, the minimum this project supports.

## Taskbar (new indicator `taskbar`)

- labwc has no IPC for the window list, so it comes from the
  `wlr-foreign-toplevel-management-unstable-v1` Wayland protocol, which labwc
  and sway both implement. The protocol XML is vendored in
  `app/modules/topbar/protocols/`; `wayland-scanner` generates the C at build time.
- `toplevel-tracker.c` is the one piece of C: it binds the protocol on GDK's
  own `wl_display`, so GDK's event loop dispatches it, with no thread and no
  polling. `toplevel-tracker.vapi` exposes it to Vala.
- `toplevels.vala` is the shared model, one per process for all monitors.
  Changes are coalesced into one `changed` per main-loop turn.
- `indicators/taskbar.vala`: one button per app id, in opening order. Click
  raises the app's most recently focused window; clicking the app in front
  cycles its windows, or minimises it if it has one. App → icon goes
  `<app_id>.desktop`, lowercase, `StartupWMClass`, reverse-DNS suffix,
  icon theme, then `application-x-executable`; the result is cached per app,
  misses included.
- Added to the default `layout-start`: `['launcher','workspaces','taskbar']`.
  A user who has customised that key must add `taskbar` themselves.

## Base Center removed

- Deleted `app/modules/base-center/`, its `.desktop` file, the `base-center`
  meson option, the four `screenshots/base-center - *.png` references (still
  in git history), and the Base Center shell CSS.
- Deleted `lib/ui` card, rows, chip, stat-tile and meter-ring. Base Center was
  their only user, and they were compiled into the resident topbar. With the
  meter ring gone, nothing uses cairo, so that dependency went too. The
  generic component CSS (cards, rows, chips, controls) stays in the design
  system.
- Kept `centaur-sysd` and `centaur-settingsd`. settingsd still applies the
  GSettings keys. **sysd now has no client**; whether to remove it is open.
- Docs updated: architecture.md (§4.2 marked removed), module-list.md,
  app/README.md, design-system README and components.md, packaging text.

## Installer

- `install.sh --check` now requires `wayland-scanner`, `wayland-client` and
  `gtk4-wayland`, and no longer checks for cairo. Per-distro hints updated.
- `install.sh` deletes a leftover `centaur-base-center` binary and `.desktop`
  from an earlier install; meson itself never removes files.
- PKGBUILD: `wayland` added to depends and makedepends; cairo dropped.
