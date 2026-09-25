# Task log — Power menu actions did nothing

**Date:** 2026-09-24
**Task:** "On the topbar power button menu option like shutdown, reboot,
logout, lock and suspend is not working. check the issues and fix the bugs."

## Findings

**1. Every item crashed the topbar.** The journal had a core dump of
`centaur-topbar` at 18:29:18 in `centaur_topbar_power_indicator_run` →
`g_spawn_async`. `action_button (label, icon, string[] argv)` captured `argv`
in the click closure. Vala stores a captured array parameter by pointer
(generated C: `_data5_->argv = argv;`), and each call site passed a temporary
array literal that was freed once the menu was built. A click handed freed
memory to `g_spawn_async`, the topbar segfaulted, and centaur-session restarted
it within a second, so from the user's side the click simply did nothing.

**2. Lock could not have worked anyway.** `loginctl lock-session` only
broadcasts logind's Lock signal for a locker to act on. No locker was
installed or listening.

**3. Failures were invisible.** Errors went to a log only, and `notify-send`
fails because Centaur has no notification daemon yet.

Not the cause: logind itself. `CanPowerOff`, `CanReboot` and `CanSuspend` all
return `yes`, and session `c1` is active on seat0.

## Fixes

- Each item now takes an owned closure. The command array is built at click
  time and passed `owned` to an async `run`, which frees it when done. The
  generated C was scanned for other arrays stored without a copy; volume's
  helpers were safe but are now `owned` too.
- Lock runs a locker directly (`swaylock --daemonize --color 0a0e12`, else
  gtklock, waylock or hyprlock). It falls back to `loginctl lock-session` for
  setups where swayidle answers it, and says when no locker is installed.
- `run` uses `Subprocess`, collects stderr, and shows a `Gtk.AlertDialog` when a
  command fails or cannot start.

## Verified

A probe built from the real `PowerIndicator` clicked Lock after heavy
allocation churn, the condition that exposes a dangling pointer. The process
survived and reported the missing locker. Log Out, Suspend, Restart and Power
Off go through the same fixed path but were not fired, for obvious reasons.

## Installer

- PKGBUILD depends on `swaylock`. `install.sh --check` reports it when missing.
- Version 0.1.2 → 0.1.3.
