# Task log — The installer sets up swaylock for Lock

**Date:** 2026-09-24
**Task:** "when run the installer it must install swaylock and configure it to
properly lock the screen when user click the lock menu option in the topbar
power menu."

## Lock screen config, generated from the design tokens

`design-system/tools/generate.py` now also writes
`app/data/themes/swaylock.conf`, installed as
`/usr/share/centaur/themes/swaylock.conf`. The generator's staleness check
covers it: 30 files, all current.

- It uses the dark palette regardless of desktop mode: window-surface
  background, card-coloured indicator, Inter font, and no separator lines.
- Colours: accent while verifying; `status.danger` for a wrong password and
  backspace; `status.warning` for caps lock.
- It shows failed attempts, ignores an empty Enter, and keeps the indicator
  visible while idle.
- All 35 keys, and every option the topbar passes, were checked against the
  long-option table in swaylock's `main.c`.

## Topbar

Lock now runs `swaylock --daemonize --config <that file>`. It also passes
`--key-hl-color`, `--caps-lock-key-hl-color`, `--ring-ver-color` and
`--text-ver-color` in the user's current accent, read from
`accent-map.json`. swaylock applies arguments after the config file, so an
accent change needs no regeneration. If `~/.config/swaylock/config` or
`~/.swaylock/config` exists, it is used untouched. `Ui.Theme.theme_dir()` is
now public for this lookup.

## Installer

A new "lock screen" step runs after `meson install` (skip it with
`--no-lock-screen`):

1. It installs swaylock through pacman (`-S --needed`, no `-y`), apt, dnf or
   zypper. On failure it says so; on Arch it suggests `-Syu` for a stale
   database.
2. It makes sure a swaylock PAM service exists. Without one, swaylock locks but
   can never unlock. Every distribution package ships one; if it is missing,
   it writes upstream's own (`auth include login`, or `@include common-auth`
   on Debian).
3. It reports whether a personal swaylock config will override Centaur's,
   looking in the invoking user's home, not root's under sudo.

Dry-run with `sudo` stubbed out: the absent → install and present → PAM
paths both behave as intended. `uninstall.sh` leaves swaylock installed and
says so. Version 0.1.3 → 0.1.4.

**Not done:** actually locking the screen. That would have locked the user's
live session.
