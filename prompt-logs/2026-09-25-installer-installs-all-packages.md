# Task log — Installer installs every package with pacman

**Date:** 2026-09-25
**Task:** "all Required and Optional packages must be install from the pacman
by installer. update the project according to this."

## Design

`packaging/arch/PKGBUILD` is now the single list of what Centaur needs:
- `depends`: required at runtime (17 packages, grouped as compositor,
  libraries, session tools and look);
- `makedepends`: build;
- `optdepends`: optional.

`install.sh` reads those arrays from the PKGBUILD in a subshell, so the
package and the installer can no longer disagree. Added to `depends`:
`gdk-pixbuf2` (thumbnails) and `librsvg` (the SVG wallpapers). Both were only
there before because gtk4 happened to pull them in.

## install.sh, rewritten around it

1. It reports, per group, what `pacman -T` says is missing (build, required,
   optional). `--check` stops there.
2. It installs everything missing in one call:
   `pacman -S --needed --noconfirm`, with no `-y` (partial-upgrade hazard). On
   failure it suggests `pacman -Syu`, and stops only if a build or required
   package is still missing.
3. It builds and installs as before.
4. **Setting up:**
   - compositor status;
   - the swaylock PAM check;
   - NetworkManager, enabled only when no other network service
     (systemd-networkd, dhcpcd, connman, netctl, iwd) is active; otherwise
     it prints how to switch;
   - the VM Suspend notice.
5. It reloads the running session as before.

Optional packages it deliberately does not install:
- **sway**: an alternative compositor, while labwc is the official one.
- **pipewire-pulse** when `pulseaudio` is installed: they conflict, and
  `--noconfirm` would turn the conflict into a failed install. `libpulse`
  (pactl) works with either.

Also:
- `gcc` and `pkgconf` are added to the build set; makepkg assumes
  base-devel, and a plain install cannot.
- New `--no-optional`. The `--no-lock-screen` and `--no-wallpaper` flags are
  gone: swaylock and swaybg are required packages now.
- Without pacman the installer stops and says what to install instead;
  the Debian, Fedora and openSUSE branches are removed.

## Verified on this machine

- `--check`: build all installed; required missing `xorg-xwayland
  pacman-contrib inter-font`; optional missing `networkmanager upower
  ttf-jetbrains-mono papirus-icon-theme`. This matches the manual audit.
- With `sudo` stubbed: a single
  `pacman -S --needed --noconfirm` of exactly those 7 packages.
- NetworkManager logic: with systemd-networkd active (this machine) it
  installs but does not enable, and prints the switch commands; with no other
  service it enables.
- With pulseaudio present, the optional list drops pipewire-pulse; sway is
  always dropped.
- `bash -n`, `--help`, and `makepkg --printsrcinfo` (30 dependency entries)
  all pass.

The full script was not run end to end: it would install packages, and its
reload step would restart the live topbar.

Version 0.1.8 → 0.1.9.
