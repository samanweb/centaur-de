# Centaur DE — application tree

Version 0.1.0. Implements Phase 0 and the core of Phase 1 from
[`../architecture.md`](../architecture.md) §11.

> **This code has never been compiled.** It was written on a machine without
> `valac`, `meson` or `gtk4-layer-shell`, and nothing installed them. Everything
> that *could* be verified was — see [Verification](#verification) — but expect
> to fix compile errors on the first build. Treat 0.1.0 as a complete draft, not
> a tested release.

---

## Build and install

On Arch, build a package so it can be removed cleanly:

```sh
cd packaging/arch && makepkg -si
sudo systemctl enable --now centaur-sysd.service
```

Anywhere else:

```sh
./install.sh --check      # verify prerequisites, change nothing
./install.sh              # build and install under /usr
sudo systemctl enable --now centaur-sysd.service
```

Then log out and choose **Centaur** in your display manager.

`./uninstall.sh` removes exactly what `install.sh` installed, using meson's own
install log.

### Running without installing

```sh
meson setup build . && meson compile -C build
CENTAUR_THEME_DIR=$PWD/data/themes \
CENTAUR_LIBEXECDIR=$PWD/build/daemons \
  ./build/modules/topbar/centaur-topbar
```

`GSETTINGS_SCHEMA_DIR` must also point at a compiled copy of
`data/schemas/`, or GSettings will abort on the missing schema.

---

## What is here

| Component | State |
|---|---|
| `lib/core` | Distro detection, GSettings access, D-Bus interface definitions |
| `lib/ui` | Theme loader, Card, Row, ToggleRow, SliderRow, ComboRow, Chip, StatTile, MeterRing |
| `lib/compositor` | Backend interface, sway (full), labwc (configuration only) |
| `daemons/sysd` | Host, Packages, Security; polkit-gated; pacman/apt/dnf/zypper backends |
| `daemons/settingsd` | Applies configuration to GTK and the compositor |
| `modules/topbar` | launcher, workspaces, focused-window, network, volume, battery, clock, power |
| `modules/base-center` | Overview, Appearance, Security & Privacy |
| `session` | Session entry point and shell supervisor |

### What is not here

Phase 2 and 3 from `architecture.md` §11 are untouched: `centaur-notifyd`,
`centaur-portald`, `centaur-bg`, and the standalone `centaur-launcher`.

Five pages from the reference screenshots are **absent rather than empty** —
Displays & Hardware, Network & Wi-Fi, Bluetooth, Sound & Audio, Power & Battery.
A settings window that lists a page and then shows nothing is worse than one
that is honestly smaller. Displays needs a `wlr-output-management-v1` client;
the other four need their respective D-Bus services wired up.

The START button opens a working application list built on `GLib.AppInfo`, which
covers what a launcher is for. The standalone `centaur-launcher` module is still
Phase 2.

---

## Known gaps

**Workspaces and focused-window do not work under labwc.** This is the largest
functional gap in 0.1.0. Reading them needs the `ext-workspace-v1` and
`wlr-foreign-toplevel-management-v1` Wayland protocols, which means
`wayland-scanner` and hand-written C — the one case `architecture.md` §2 admits
C for, and not something worth writing untested. `LabwcBackend` reports both
capabilities as false, so the two indicators are **absent** rather than empty.
Under sway both work today through its IPC socket.

This is the `Capabilities` mechanism doing exactly its job, but it is still a
gap, not a feature.

**The volume indicator drives `pactl`.** A native WirePlumber binding is the
right answer and is Phase 2 work. The shortcut is event-driven — one long-lived
`pactl subscribe` — so it costs a process and a parse, not a wakeup per second.

**Search filters to a page, not to a row.** `architecture.md` §4.2 describes
search jumping to the matched setting and highlighting it. Today it filters the
sidebar. The page metadata needed for the finer behaviour is already declared.

**`centaur-sysd` has no Firewall or Services interface yet.** The Security page
reports which firewall tool is installed but cannot manage rules.

**Refreshing the update list on Arch needs `pacman-contrib`.** `pacman -Sy`
without an upgrade in the same transaction is the partial-upgrade hazard, so
Centaur will not run it. With `checkupdates` present the refresh syncs into a
temporary database; without it, the check degrades to reading the local database
and reports only what is already known.

**Content does not cap its width on an ultrawide display.** `set_size_request`
is a minimum, not a maximum, and a real cap needs a custom `Gtk.LayoutManager`
because this build uses no libadwaita and so has no `AdwClamp`.

---

## Deviations from architecture.md

Each of these was a deliberate trade, and each is reversible.

**Source sets compiled per target, instead of three libraries.**
`architecture.md` names `libcentaur-core`, `libcentaur-ui` and
`libcentaur-compositor`. They exist as three namespaces and three source sets in
`lib/meson.build`, compiled into each executable rather than built as libraries.

This started as one static archive and did not survive contact with a compiler.
Vala generates a single public header for a library, so `centaur.h` carried
every public type — including `Ui.Chip` and its `GtkLabel parent_instance` —
and `core/log.c`, which uses no GTK and therefore includes no `gtk/gtk.h`,
included that header anyway. `GtkLabel` was an incomplete type and the C compile
failed. Source sets give each `.c` file exactly the declarations and includes it
needs, with no shared header to get this wrong.

*This is now closer to the architecture than the archive was.* Because
`centaur-sysd` and `centaur-settingsd` never compile the `ui` sources, they link
no GTK at all — the property `architecture.md` §2.3 asks for, which the archive
had quietly cost. Only `centaur-topbar` and `centaur-base-center` depend on GTK.

*Cost:* the shared sources are compiled once per target. They are small, and a
root process that does not link a UI toolkit is worth more than the build
seconds. Turning the three source sets into three real libraries remains
possible; it is a build-file change, not a refactor.

**D-Bus interfaces are defined in Vala, not in XML.** `architecture.md` §6.2
says client and server are generated from XML in `data/dbus/`. In a Vala project
that means two sources of truth, because Vala's own `[DBus]` interfaces already
serve as both proxy and server definition. `lib/core/system-client.vala` is the
single definition; the XML is available at runtime through D-Bus introspection
(`busctl introspect org.centaur.System1 /org/centaur/System1`), so the intent —
one definition, no drift — is preserved by a different mechanism.

**Three interfaces share one object path.** `Host`, `Packages` and `Security`
are separate D-Bus interfaces, as designed, but all live at
`/org/centaur/System1` rather than at three paths. D-Bus supports this directly
and it removes two paths to keep in step.

**`centaur-session` supervises directly rather than through systemd user
units.** This matches `architecture.md` §2.4, which specifies backoff and a cap
— behaviour that would have to be re-expressed as unit options. The cap is three
restarts per minute, after which the module stays down and a notification is
posted.

---

## Verification

Nothing here has been compiled or run. What *was* checked:

| Checked | How | Result |
|---|---|---|
| GSettings schema | `glib-compile-schemas --strict --dry-run` | compiles |
| D-Bus bus policy | `xmllint --noout --nonet` | well-formed |
| polkit policy | `xmllint --noout --nonet` | well-formed |
| `centaur-base-center.desktop` | `desktop-file-validate` | valid |
| `centaur.desktop` | `desktop-file-validate` | valid apart from `DesktopNames`, which the validator does not model for session files and which display managers require |
| `PKGBUILD` | `bash -n`, `shellcheck`, `makepkg --printsrcinfo` | clean |
| `install.sh`, `uninstall.sh` | `bash -n`, `shellcheck`, live `--check` run | clean |
| Design system | `generate.py --check`, `check_contrast.py` | 29 files current, 93/93 contrast |

**Not checked:** every line of Vala, and every `meson.build`.

### First build

A review pass has since removed 18 defects found by inspection — see
[`../prompt-logs/2026-09-24-bug-hunt-and-fixes.md`](../prompt-logs/2026-09-24-bug-hunt-and-fixes.md).
Five of them would have been wrong at runtime rather than at compile time,
including sway replies being read into a throwaway buffer and a `pacman -Sy`
that risked a partial upgrade. That raises the odds but does not change the
status: **still never compiled.**

Remaining risk, in order of likelihood:

1. Async D-Bus method signatures in `daemons/sysd`.
2. `Capabilities` as a struct-typed property on an interface.
3. `gtk4-layer-shell`'s VAPI namespace, if your distribution packages it
   differently from `GtkLayerShell`.
4. Meson's Vala handling of the generated `version.vala` across targets.

The design system's meson tests run as part of `meson test`, so a build that
gets that far already has its stylesheets verified.
