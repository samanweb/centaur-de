# Task log — Display settings (monitors, resolution)

**Date:** 2026-09-24
**Task:** "add tools to manage displays(monitors) change display
resolution.(display configuration)."

## What was built

**`centaur-displays`** (`app/modules/displays/`) is a GTK4 window started on
demand from the launcher ("Displays", `centaur-displays.desktop`).

- **Arrangement:** monitors drawn to scale as tiles you can drag; a dropped
  tile snaps edge-to-edge against its nearest neighbour, never overlapping,
  with edges aligned within 64 logical px.
- **Per display:** on/off (the last display cannot be switched off),
  resolution (largest first, monitor's own marked Recommended), refresh rate,
  scale 100–200%, orientation. Values set elsewhere, such as an odd scale or
  a mirrored transform, stay selectable rather than being lost.
- Changing a display's size moves whatever touched its right or bottom edge,
  so the layout stays joined.
- **Apply** runs the compositor's `test` request, then `apply`, then asks
  "Keep these display settings?" with a 15-second countdown. Revert, closing
  the dialog, or no answer restores the previous layout; the main window
  cannot be closed while the question is open. **Keep** saves the layout.

**Native layer** (`app/lib/wayland/output-manager.{c,h,vapi}`, GLib and
libwayland only): a `wlr-output-management-unstable-v1` client, bound at v4
(labwc 0.20 offers v4). It crosses into Vala as GVariant snapshots and
configurations, and fills in every head the caller leaves out, because the
protocol makes an unconfigured head an error. It works on GDK's `wl_display`
or on its own connection dispatched from the GLib main loop.

**Model** (`app/lib/displays/`): `Head`/`Mode` values, config building,
normalisation to the origin, and `Store`. Saved layouts live in
`~/.config/centaur/displays.json`, keyed by make|model|serial (the connector
name when there is no serial), with modes stored as size+refresh, never as
an index. Saves merge, so an unplugged monitor keeps its entry. The write is
atomic, and a restore can never leave every display off.

**Persistence** (`app/daemons/settingsd/displays.vala`): the protocol only
changes the running session, so `centaur-settingsd` applies the saved
layout at login and whenever the set of connected monitors changes. It does
not react to every layout change, which would fight the settings window and
loop on its own applies. settingsd still links no GTK.

Protocol XML now lives in `app/protocols/` with one generation rule for all
protocols; the topbar's toplevel protocol moved there too.

## Bug found in testing

Changing a dropdown pinned a CPU forever. Every edit arrives in the
dropdown's `notify::selected`, and the refresh replaced that same dropdown's
model from inside it, which sends GTK into an endless resync with its popup
list. Core-dump sampling showed flat memory, 100% CPU and a single call
chain from `on_scale_changed`. Fix: models are only replaced when their
entries differ, and edits refresh from an idle.

## Verified

- **Real compositor, test requests only:** it read Virtual-1 (QEMU, 26 modes,
  1280×800 @ 74.99 Hz). A 5120×2160 test and a 150% scale test both returned
  `succeeded`; nothing was changed.
- **Nested headless labwc with two outputs:** applying position, scale 2.0
  and rotation, disabling and re-enabling a display, saving, then
  `DisplayApplier` restoring the saved layout all worked.
- **The real window on the nested compositor:** 125% → Apply → dialog →
  Keep saved it; 150% → Apply → Revert returned the live scale to 125%.
- Clean build and staged install. Design-system gates pass (30 generated
  files, 93/93 contrast). The `.desktop` file validates and the schema
  compiles strictly.

**Not tested:** real multi-monitor hardware, and the automatic revert on
timeout.

## Installer / packaging

No new dependencies: gtk4-wayland, wayland-client and wayland-scanner were
already required. The installer, pacman message and uninstaller mention
Displays and where layouts are saved. The PKGBUILD description is updated.
Version 0.1.5 → 0.1.6.
