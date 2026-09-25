# Task log — Suspend "crashes" the system

**Date:** 2026-09-24
**Task:** "when power menu option suspend click system crash. check this issue
and find proper solution to fix it."

## What happened

Boot -1 of the journal ends with:

    18:49:03 systemd-logind: suspend requested from client PID 1877 ('systemctl')
    18:49:03 systemd-sleep: Performing sleep operation 'suspend'...
    18:49:03 kernel: PM: suspend entry (s2idle)

There is nothing after that: no resume and no error. The next boot starts at
18:49:25. The suspend itself succeeded; the machine never came back.

The machine is a QEMU/KVM guest (`systemd-detect-virt` → `kvm`, DMI "QEMU
Standard PC (Q35 + ICH9)", virtio GPU). Its firmware supports only S0 and S5,
so `mem_sleep` is `[s2idle]`. A guest in s2idle has no wake source unless the
host sends one (`virsh dompmwakeup` or QEMU's `system_wakeup`), because the
virtual keyboard and mouse cannot wake it. It stays frozen until reset, which
from inside looks like a crash.

The topbar offered Suspend because logind's `CanSuspend` said "yes". logind
answers "yes" whenever the kernel lists any sleep state, s2idle included, so
it was not evidence that the machine could come back.

## Fix

- `PowerIndicator` keeps Suspend hidden until a probe says it is safe. The
  probe asks, over D-Bus (no subprocess, once per process):
  1. logind `CanSuspend`: must be `yes` or `challenge`;
  2. systemd `Manager.Virtualization`: must be empty, i.e. not a VM or
     container.
- New key `org.centaur.topbar suspend-button`: `auto` (default, the probe
  above), `always`, or `never`. The menu follows changes live.
- Suspend now locks first (`swaylock --daemonize` returns once locked), so
  waking never shows an unlocked session.

## Verified

A probe with the real `PowerIndicator` on this VM found Suspend hidden under
`auto`, shown under `always` and hidden under `never`. The schema passes
`glib-compile-schemas --strict`.

## Installer

- `install.sh` prints a notice under virtualisation, with the override command.
- The pacman install message documents the same.
- Version 0.1.4 → 0.1.5.
