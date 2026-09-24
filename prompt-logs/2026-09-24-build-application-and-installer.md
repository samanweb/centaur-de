# Task log — Build the application with a Linux installer

**Date:** 2026-09-24
**Task:** "Build the application with a linux compatible installer. do not install anything [on] this pc — this will install on another arch pc later"
**Version produced:** 0.1.0 — Phase 0 plus the core of Phase 1
**Outcome:** Full source tree in `app/`, Arch PKGBUILD, generic installer/uninstaller.

## The governing constraint

Nothing could be installed, so nothing could be compiled: `valac`, `meson` and
`gtk4-layer-shell` are all absent from this machine. **No Vala or meson file
here has ever been built.**

That shaped the engineering more than any other factor. Two consequences worth
remembering:

1. Where a design choice traded architectural purity for build reliability,
   build reliability won — see Deviations below. An untested tree that compiles
   is worth more than an elegant one that does not.
2. Verification effort went into the layers that *could* be checked. All of the
   data and packaging layer is validated; see the table in `app/README.md`.

## What was built

```
app/
  lib/{core,ui,compositor}     distro, config, D-Bus defs, widgets, compositor adapters
  daemons/sysd                 polkit-gated root service, 4 package backends
  daemons/settingsd            config translator
  modules/topbar               8 indicators, layer-shell, per-monitor
  modules/base-center          shell + Overview, Appearance, Security pages
  session                      entry point + supervisor
  data/                        schemas, polkit, dbus, systemd, desktop files
packaging/arch/PKGBUILD        + centaur-de.install
install.sh, uninstall.sh
```

## Decisions made under the no-compile constraint

**One static archive, not three libraries.** Meson's Vala support is most
fragile around inter-library VAPI dependencies, which is exactly what three
libraries would need. One archive removes that failure mode. Costs settingsd a
GTK link it does not use. Reversible as a build-file change.

**D-Bus interfaces defined in Vala, not generated from XML.** `architecture.md`
§6.2 wanted XML as the source. In Vala that creates two sources of truth,
because `[DBus]` interfaces already serve as both proxy and server. The intent —
one definition, no drift — is preserved; the mechanism differs. Introspection
still yields the XML at runtime.

**sway implemented fully, labwc configuration-only.** This is the significant
functional gap. labwc has no IPC, so workspaces and focused-window need
`ext-workspace-v1` and `wlr-foreign-toplevel-management-v1` — raw Wayland
protocol code in C. Writing that untested was not defensible. `LabwcBackend`
reports both capabilities false and the topbar omits those two indicators, which
is the `Capabilities` mechanism from §5 working as designed. Under sway both
work today.

**Five Base Center pages absent rather than stubbed.** A settings window that
lists a page and then shows nothing is worse than an honestly smaller one.

## Bugs found and fixed by inspection

Worth recording, because these are the class of error that compiling would have
caught immediately and reading nearly missed:

1. **`Job` exported unmarshallable members.** In a `[DBus]` class every public
   member is exported; `export(DBusConnection)` cannot be marshalled. Added
   `[DBus (visible = false)]` to five members.
2. **Property name mismatch across the interface boundary.** `PackagesIface`
   declared `backend` (wire name `Backend`); the service implemented
   `backend_name` (`BackendName`). Any client reading it would have failed at
   runtime. Renamed the service property; renamed the field to `selected` so it
   stops shadowing a local.
3. **A Vala lambda assigned to `var`** in the Appearance page — no delegate type
   to infer, so it would not compile. Replaced with a method.
4. **`FontDialogButton.font-desc` bound to a string key.** `font-desc` is a
   `Pango.FontDescription`; GSettings would refuse the binding at runtime.
   Replaced with explicit conversion in both directions.
5. **Accent swatches referenced CSS that did not exist.** Only the *selected*
   accent is `centaur_accent_base`; the page shows all eight. Extended the
   generator to emit `centaur_swatch_<accent>` per palette plus the matching
   rules — generated, so the list cannot drift from the ramps.
6. **`MeterRing` track colour could not come from a CSS class**, because a ring
   is one drawing area. Changed the design system to derive it from the widget's
   own colour at 18% alpha and updated `components.md` to match, rather than
   leaving a rule that nothing reads.

## Verification

Everything checkable was checked, and all of it passes:

- GSettings schema **compiles** (`glib-compile-schemas --strict --dry-run`)
- D-Bus bus policy and polkit policy well-formed (`xmllint --nonet`)
- `.desktop` files valid (`desktop-file-validate`); the session file is flagged
  only for `DesktopNames`, which the validator does not model for session files
  and which GDM/SDDM/LightDM require
- `PKGBUILD` clean under `bash -n`, `shellcheck` and `makepkg --printsrcinfo`
- `install.sh` / `uninstall.sh` clean under `shellcheck`; `--check` run live and
  correctly reported `meson`, `valac` and `gtk4-layer-shell` missing here
- Design system: 29 generated files current, 93/93 contrast checks

**Not verified: every line of Vala, and every `meson.build`.**

## Next step

On the target Arch machine: `cd packaging/arch && makepkg -si`. Expect compile
errors on the first build. `app/README.md` lists where they are most likely —
the async D-Bus methods in `daemons/sysd`, the binary IPC in
`lib/compositor/sway.vala`, and the `gtk4-layer-shell` VAPI namespace.

After it builds, the first real gap to close is labwc workspace support.
