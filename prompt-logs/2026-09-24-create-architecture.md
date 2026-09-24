# Task log — Create architecture for the project

**Date:** 2026-09-24
**Task (from `claude.md`):** "create architecture for this project"
**Outcome:** `architecture.md` written; `module-list.md` expanded to a full index.

## Inputs read

- `introduction.md`, `module-list.md`, `claude.md`
- `screenshots/base-center-System-Overview.png`
- `screenshots/base-center-Displays-&-Hardware.png`
- `screenshots/base-center-Security-&-Updates.png`
- `screenshots/base-centerAppearance-&-Theming.png`
- `prompt-logs/topbar.png` — topbar reference image (note: this is a design
  reference sitting in the logs directory; it probably belongs in `screenshots/`)

Toolchain probed on the machine: GTK4 4.22.5, Wayland 1.26.0, GLib 2.88.3,
Ninja 1.13.2, GCC 16.2.1 present. `valac`, `meson`, `gtk4-layer-shell`, wlroots
dev packages absent.

## Decisions taken (each one chosen by the user)

1. **Centaur is a shell on an existing compositor**, not its own compositor.
   labwc is the reference target, sway second. Rejected: writing a wlroots
   compositor (multi-month subsystem before any shell UI works); rejected an
   abstraction layer built now for a future native compositor.
2. **Vala everywhere, C only when forced.** Reconciles `introduction.md` saying
   both "C as main language" and "GTK4 + Vala" — valac emits C, so C is shipped.
   Rejected: C for daemons / Vala for UI; rejected plain C everywhere.
3. **One D-Bus system daemon with distro backend plugins** for privileged work.
   Rejected: relying only on existing services (PackageKit is weak on Arch, and
   LUKS/TPM and audit have no home); rejected the hybrid split as a fuzzier
   boundary.
4. **Full DE architecture, phased** rather than documenting only the two modules
   currently in `module-list.md`.
5. **One binary per module, coupled over D-Bus** (approach A). Rejected: single
   shell process (forces the resident topbar to carry Base Center's footprint,
   and one crash kills the desktop); rejected an `.so` plugin host (pays the
   fragility of the single process plus the complexity of an ABI).

## Design points worth remembering

- GSettings/dconf is the config store; `centaur-settingsd` is a translator, not
  a store. One writer, many reactors.
- `centaur-sysd` links no UI — GLib/GIO only — and spawns backends via argv
  arrays, never `sh -c`.
- `CompositorBackend.capabilities` lets the Appearance page grey out what the
  running compositor cannot do instead of writing dead keys.
- Displays use `wlr-output-management-v1` directly, bypassing the backend, since
  both targets implement it.
- Long privileged operations are Job objects living in `sysd`, so closing Base
  Center mid-upgrade does not kill the upgrade.
- `design system/tokens.json` is the single styling source; three colour modes
  times eight accents cannot be hand-written CSS.
- The four screenshots become executable spec via headless visual diffing.
- Topbar budget — under 40 MB RSS — is asserted by a test, not just intended.

## State after this task

- `architecture.md` — complete, 14 sections, approved design.
- `module-list.md` — 12 components with phase markers.
- `app/` — still empty. Phase 0 has not started.
- `design system/` — still empty. `tokens.json` is the first Phase 0 task.

## Next step

Phase 0: install the missing toolchain (§12), then the Meson skeleton,
`libcentaur-core` / `libcentaur-ui`, `tokens.json` and its CSS generator,
`centaur-session`, the labwc adapter, and the CI headless harness.

## Open questions carried forward

- Does `centaur-bg` stay a separate process or fold into `settingsd`?
- Does the launcher include a run-command entry or stay application-only?
- What visual-diff tolerance keeps the baseline stable across font versions?
