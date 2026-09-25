# Task log — Taskbar icons not appearing; reload on install

**Date:** 2026-09-24
**Task:** "when user open up new application that application's icon must be
display in the topbar. if user minimize the application user will be able to
reopen the application window from clicking application icon in the topbar.
... do the task and update the project and installer."

## Why the icons never appeared

The taskbar from the previous task was installed and running, and the
`taskbar` id was in `layout-start`, yet it showed nothing. The indicator set
`visible = false` while it had no windows, which it always has at startup.
It subscribes to the window list on `map`, and GTK never maps a hidden widget,
so it never heard about a window and stayed hidden for the whole session.
`FocusedWindowIndicator` had the same bug.

**Fix:** both now stay mapped and toggle an `.empty` css class that collapses
their padding and margin instead of hiding.

## Verified end to end on the live labwc session

A probe built from the real topbar sources (`Toplevels`, `TaskbarIndicator`)
opened its own window and:

1. showed a button for every open app, its own marked `.active`;
2. minimised itself through the protocol: `minimized=true`;
3. clicked its own taskbar button: `minimized=false activated=true`.

It touched no other window.

## Installer

- `install.sh` now reloads a running session: if the invoking user has a live
  `centaur-session --shell`, it stops `centaur-topbar` and `centaur-settingsd`,
  and the session respawns them within a second from the new binaries.
  Processes are matched by command line because the kernel truncates
  `centaur-settingsd` to 15 characters.
- The pacman `post_upgrade` prints `pkill -x centaur-topbar` as the reload step.
- Version 0.1.1 → 0.1.2.
