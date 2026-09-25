# Centaur DE — Architecture

**Status:** approved design, not yet implemented
**Date:** 2026-09-24
**Applies to:** Debian, Fedora, openSUSE, Arch · Wayland only

---

## 1. Purpose and constraints

Centaur DE is a lightweight desktop environment for Wayland, targeting Debian,
Fedora, openSUSE and Arch. It must be comfortable for coding, image editing,
audio and video work, office documents and web browsing while using very few
resources.

Centaur supplies the *desktop*, not the applications. Those workloads are served
by whatever the user installs; Centaur's job is to stay out of their memory
budget and their way.

Four constraints drive every decision below.

| Constraint | Consequence |
|---|---|
| Very low resource usage | Resident processes stay minimal; occasional UI is spawned and exits; nothing polls. |
| Wayland only | No X11 compatibility layer in Centaur itself. XWayland is the host compositor's concern. |
| Four distro families | Every distro-specific behaviour lives behind one interface, selected at runtime. |
| GTK4 + Vala, C as the shipped language | See §2. |

### Language

`introduction.md` asks for C as the main language while using GTK4 + Vala. These
are the same thing, and the document should be read that way: **`valac` compiles
Vala to C**, and C is what is compiled and shipped.

The working rule is **Vala everywhere, C only when forced**. Drop to hand-written
C only where Vala bindings are absent or obstructive — raw Wayland protocol code
against generated `wayland-client` headers being the main case. GObject
boilerplate is not a reason to write C by hand; it is the reason not to.

---

## 2. System architecture

```
┌─ Layer 3: UI modules (user session, on demand) ─────────────────────┐
│  centaur-topbar      centaur-base-center     centaur-launcher       │
│  (resident, tiny)    (spawned, then exits)   (spawned, then exits)  │
└─────────────────────────────┬───────────────────────────────────────┘
                              │ session bus
┌─ Layer 2: session services (user session, resident) ────────────────┐
│  centaur-session    supervises the compositor and everything below  │
│  centaur-settingsd  owns config, applies it   org.centaur.Settings1 │
│  centaur-notifyd    org.freedesktop.Notifications                   │
│  centaur-portald    xdg-desktop-portal backend                      │
│  centaur-bg         wallpaper, layer-shell background surface       │
└─────────────────────────────┬───────────────────────────────────────┘
                              │ system bus, polkit-gated
┌─ Layer 1: privileged ───────────────────────────────────────────────┐
│  centaur-sysd   org.centaur.System1   (root; GLib/GIO only, no GTK) │
│     └─ distro backends: pacman│apt│dnf│zypper, ufw│firewalld, …     │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
┌─ Layer 0: host system ──────────────────────────────────────────────┐
│  labwc (reference) / sway    systemd    D-Bus    PipeWire           │
│  NetworkManager    logind    UPower    UDisks2    polkit            │
└─────────────────────────────────────────────────────────────────────┘

Shared libraries
  libcentaur-core        config access, D-Bus clients, distro detection, logging
  libcentaur-ui          design tokens and the Card / Row / Tile / Meter widgets
  libcentaur-compositor  CompositorBackend interface + labwc and sway backends
```

### 2.1 Centaur is a shell, not a compositor

Centaur does **not** ship a Wayland compositor. It runs on an existing
wlroots-based compositor and configures it.

- **labwc is Centaur's official compositor** (decided 2026-09-25). It is
  small, mature, implements every protocol Centaur relies on
  (`wlr-layer-shell`, `wlr-foreign-toplevel-management`,
  `wlr-output-management`, `ext-session-lock`), and is configured through plain
  files that Centaur can rewrite. The installer and the package install it,
  with Xwayland for X11 applications, and `centaur-session` starts it.
- **sway still works** as an alternative (also wlroots, so one adapter covers
  most of both), but it is not installed or set up for you: its config needs
  the `exec` lines in `app/README.md`.

The Appearance page's compositor settings — window placement, titlebar buttons,
transition duration — are therefore a *configuration adapter*, not a window
manager. §5 covers what that means when the two compositors disagree.

### 2.2 One process per job

Each module is its own executable, coupled over D-Bus.

This is the choice that most directly serves the low-resource requirement. The
topbar is resident for the entire session and must stay small; Base Center is
opened occasionally and is free to be heavy and then exit. A single combined
shell process would force the topbar to carry Base Center's footprint all
session. Separate processes also mean a crash in Base Center cannot take down
the topbar, and a module can be rebuilt and restarted during development without
ending the session.

The cost is IPC surface, which §4 pins down, and some duplicated GTK mappings —
largely shared pages in practice.

### 2.3 `centaur-sysd` links no UI

The root-owned process depends on GLib and GIO only. It never maps GTK, Pango or
a font cache. Every backend invocation spawns with an argv array — never
`sh -c` — so no user-supplied string reaches a shell.

### 2.4 `centaur-session` supervises

`centaur-session` is the entry point named by `data/sessions/centaur.desktop` in
`wayland-sessions`. It starts the host compositor, then the Layer 2 services,
then the topbar.

It restarts crashed modules with exponential backoff, capped at three restarts
per minute. Past the cap the module stays down and the topbar posts a
notification, rather than fork-bombing the session.

---

## 3. Configuration

**The config store is GSettings (dconf).** Schemas, type safety and change
notification come for free, and no bespoke parser has to be written or tested.

`centaur-settingsd` is therefore not a store. It is a **translator**: it watches
keys and applies them outward — rewriting `~/.config/labwc/rc.xml`, setting the
GTK theme and font, pushing cursor size and theme, regenerating the accent CSS.

This gives one writer and many reactors. Base Center never talks to the
compositor directly; it writes a key, `settingsd` applies it, and the topbar
observes the same key change. Any other module that later wants to react to a
setting subscribes to it without Base Center knowing.

Schemas live in `data/schemas/`, under the `org.centaur.*` prefix.

---

## 4. Module designs

### 4.1 `centaur-topbar` — module 01

A `gtk4-layer-shell` surface on layer `TOP`, anchored top/left/right with an
exclusive zone reserved, one bar per output.

Internally the bar is three boxes — start, center, end — populated by
**indicators**. An indicator is an in-process GObject implementing
`Centaur.Indicator`:

```vala
public interface Centaur.Indicator : Object {
    public abstract string  id      { get; }
    public abstract Gtk.Widget widget { get; }
    public abstract bool    visible { get; set; }
    public abstract void    activate ();
}
```

Indicators are **compiled in, not `.so` plugins**. The layout is data-driven —
a GSettings key lists indicator ids per section — but the code is not pluggable.
That buys reorderability without an ABI to maintain.

Default layout, matching the topbar reference image:

| Section | Indicators |
|---|---|
| start | `launcher` (START), `workspaces`, `quicklaunch` |
| center | `focused-window` |
| end | `network`, `volume`, `battery`, `clock`, `notifications`, `power` |

**Two rules keep the topbar cheap:**

1. **Every indicator subscribes; none polls.**

   | Indicator | Source |
   |---|---|
   | workspaces | `ext-workspace-v1` (labwc) / sway IPC, via `libcentaur-compositor` |
   | focused-window | `wlr-foreign-toplevel-management-unstable-v1` |
   | network | NetworkManager, D-Bus |
   | volume | WirePlumber |
   | battery | UPower, D-Bus |
   | notifications | `centaur-notifyd`, count property |
   | power | logind |
   | clock | the only timer — wakes on the minute boundary, never at 1 Hz |

2. **Popovers are constructed on first click, never at startup.** The resident
   cost is the bar and its labels.

**Budget: under 40 MB RSS with all indicators live.** This is asserted by the
test suite (§8), not merely intended.

### 4.2 `centaur-base-center` — module 02 (removed)

> **Removed from the project on 2026-09-24.** This section is kept as the record
> of what was designed. Settings are now changed through GSettings directly;
> `centaur-settingsd` still applies them, and `centaur-sysd` has no client.

Settings manager. Layout follows the reference screenshots: a sidebar with two
groups, a header bar with global search, and a scrolling grid of cards.

| Sidebar group | Pages |
|---|---|
| System Configuration | Overview, Appearance, Displays & Hardware, Security & Privacy |
| Hardware & Connectivity | Network & Wi-Fi, Bluetooth, Sound & Audio, Power & Battery |

**Pure GTK4, no libadwaita.** The screenshots describe a custom design language;
adopting libadwaita would mean shipping a GNOME dependency whose styling Centaur
would then override anyway.

A page implements `Centaur.Page`:

```vala
public interface Centaur.Page : Object {
    public abstract string     id       { get; }
    public abstract string     title    { get; }
    public abstract string     icon     { get; }
    public abstract string     category { get; }
    public abstract string[]   keywords { get; }
    public abstract Gtk.Widget create_widget ();
}
```

Pages are instantiated on first navigation. Each declares its setting rows as
descriptors, so the **search index is built from metadata** — searching "refresh
rate" jumps to Displays & Hardware and highlights that row, with no hard-coded
search table in Base Center.

Cards come from `libcentaur-ui`: `Card`, `ToggleRow`, `SliderRow`, `ComboRow`,
`StatTile`, `MeterRing` (the CPU utilisation ring and battery gauge).

Binding: user-level settings bind GSettings keys directly; privileged reads and
writes go to `org.centaur.System1`. Every call is async — a page renders its
skeleton, then fills.

### 4.3 Supporting services

| Service | Responsibility |
|---|---|
| `centaur-settingsd` | Watches config, applies it outward. Headless — no GTK — so it is unit-testable without a compositor. |
| `centaur-notifyd` | `org.freedesktop.Notifications`; exposes an unread count the topbar badge consumes. |
| `centaur-portald` | `xdg-desktop-portal` backend so sandboxed apps get Centaur's file chooser, screenshot and settings. |
| `centaur-bg` | Wallpaper, drawn on the layer-shell background layer. Split out so `settingsd` stays headless; roughly 200 lines and mergeable if that ever stops being worth a process. |
| `centaur-launcher` | The START menu and application search. Spawned on demand, exits on close. |

---

## 5. Compositor adapter

`libcentaur-compositor` defines one interface with two backends.

```vala
public interface Centaur.CompositorBackend : Object {
    // introspection
    public abstract async Workspace[] list_workspaces () throws Error;
    public abstract async void switch_workspace (string id) throws Error;
    public signal void workspaces_changed ();
    public signal void focus_changed (Toplevel? toplevel);

    // configuration, driven by the Appearance page
    public abstract async void set_window_placement (PlacementPolicy p) throws Error;
    public abstract async void set_titlebar_buttons (ButtonLayout l) throws Error;
    public abstract async void set_animation_duration (uint ms) throws Error;
    public abstract async void reload () throws Error;

    public abstract Capabilities capabilities { get; }
}
```

Backends: `LabwcBackend` (rewrites `rc.xml` / `menu.xml`, then reconfigures) and
`SwayBackend` (sway IPC socket, JSON). Selected at runtime by probing the
session.

**`capabilities` is the important member.** labwc and sway do not support the
same set of options. The Appearance page greys out what the running compositor
genuinely cannot do, rather than writing a key that silently does nothing.

**Displays are the exception.** Output configuration goes through
`wlr-output-management-unstable-v1` directly, not through a backend — both
compositors implement it, so the setting users change most often needs no
config-file rewriting on either target.

---

## 6. Privileged operations

### 6.1 One daemon, distro backends behind it

`centaur-sysd` exposes one stable API. Distro differences live in backend
modules selected at runtime from `/etc/os-release`:

| Concern | Backends |
|---|---|
| Packages | `pacman`, `apt`, `dnf`, `zypper` |
| Firewall | `firewalld`, `ufw`, `nftables` |
| Services | systemd |
| Disk encryption | LUKS / TPM inspection |

The UI never learns a distro name and never runs as root.

Where an existing system service already does the job well — NetworkManager,
logind, UPower, UDisks2 — Centaur talks to it directly rather than proxying it
through `sysd`. `sysd` covers what those services do not: native package
managers, LUKS/TPM status, firewall rules, the security audit summary, and
hardware inventory for the Overview page.

### 6.2 API sketch — `org.centaur.System1`

| Object | Key members |
|---|---|
| `.Host` | `GetHardwareInfo()`, `GetStorage()` — the Overview cards |
| `.Packages` | `CheckUpdates() → o`, `ListUpdates()`, `StartUpdate(as ids) → o` |
| `.Firewall` | `GetStatus()`, `ListRules()`, `AddRule()`, `RemoveRule()`, `SetEnabled(b)` |
| `.Services` | `ListUnits()`, `Start()`, `Stop()`, `Enable()`, `Disable()` |
| `.Security` | `GetDiskEncryption()`, `GetSecureBoot()`, `GetAuditSummary()` |

Interfaces are defined as XML in `data/dbus/`, and **both client and server are
generated from that XML** so the contract cannot drift between `sysd` and Base
Center.

### 6.3 Long-running work is a Job object

`Packages.StartUpdate()` returns an object path, not a result. The job at
`/org/centaur/System1/Jobs/N` carries `Progress`, `Status`, a `Log` signal and
`Cancel()`.

The job lives in `sysd`, so closing Base Center mid-upgrade does not kill the
upgrade, and reopening re-attaches to it.

### 6.4 Authorisation

One polkit action per capability — `org.centaur.system1.packages.update`,
`org.centaur.system1.firewall.modify`, `org.centaur.system1.services.manage`,
and so on. Reads are `yes`; mutations are `auth_admin_keep`.

`sysd`'s systemd unit runs with `NoNewPrivileges`, `ProtectHome=read-only`,
`PrivateTmp`, restricted address families and a `@system-service` syscall filter.

---

## 7. Design system

The Appearance page requires three colour modes — Auto, Pure Dark, Light — and
eight selectable accent colours. Hand-written CSS with literal hex values cannot
serve that.

**`design system/tokens.json` is the single source of truth.** It holds semantic
names (`surface.card`, `text.muted`, `accent.base`, `accent.dim`) with a value
per mode, plus the eight accent ramps.

- A build step generates GTK4 CSS from it using `@define-color`.
- At runtime `centaur-settingsd` regenerates only the accent block and hands
  every module a reloaded `Gtk.CssProvider` at
  `STYLE_PROVIDER_PRIORITY_APPLICATION`.

Changing accent colour is then a provider swap of a few milliseconds, not a
restart.

`libcentaur-ui` widgets refer to tokens by name and **never** to literal colours.
The `design system/` directory is currently empty; populating it is the first
task of Phase 0.

---

## 8. Testing

Four layers, each cheap enough to run on every change.

**Unit.** Distro backend parsers against captured fixtures —
`tests/fixtures/pacman-Qu.txt`, `apt-list-upgradable.txt`,
`dnf-check-update.txt`, `zypper-lu.txt`. Cross-distro correctness is proven here,
with no root and no virtual machine. Also covers config translation and the
search index.

**Integration.** `dbus-run-session` plus a mock `sysd` generated from the same
XML as the real one. Base Center pages are exercised against the mock, including
their error and unavailable states.

**Compositor.** Headless labwc (`WLR_BACKENDS=headless`) in CI. The topbar must
map its layer surface and react to a synthetic workspace change.

**Visual.** Each Base Center page is rendered headless and perceptually diffed
against `screenshots/`. This is what turns the reference images from decoration
into executable specification.

**Two contract tests on the security boundary:** every `System1` method must have
a polkit action, and every mutating method must reject an unauthorised caller.

**One resource test:** topbar RSS after 60 seconds idle, against the §4.1 budget.

---

## 9. Failure behaviour

Typed D-Bus errors: `NotSupported`, `Unauthorized`, `BackendMissing`, `Busy`,
`InvalidArgument`.

The rule is **degrade, never crash**. No firewalld and no ufw means the Firewall
card renders an "unavailable on this system" state — the same `Capabilities`
mechanism that greys out unsupported compositor features.

Every call is async with a timeout. Each card has spinner, content and error
states. A module that crashes is restarted by `centaur-session` under the backoff
policy in §2.4.

---

## 10. Repository layout

```
app/
  lib/       centaur-core/  centaur-ui/  centaur-compositor/
  daemons/   centaur-sysd/  centaur-settingsd/  centaur-notifyd/
             centaur-portald/  centaur-bg/
  modules/   centaur-topbar/  centaur-base-center/  centaur-launcher/
  session/   centaur-session/
  data/      schemas/  polkit/  dbus/  systemd/  sessions/  themes/
  po/
  tests/     fixtures/  unit/  integration/  visual/
  packaging/ arch/  debian/  fedora/  opensuse/
```

Build system: **Meson + Ninja**, one `meson.build` per unit.

---

## 11. Phasing

**Phase 0 — foundation.**
Meson skeleton; `libcentaur-core` and `libcentaur-ui`; `tokens.json` and the
CSS generator; `centaur-session`; `data/sessions/centaur.desktop`; the labwc
adapter covering workspaces and focus; the CI headless harness.

**Phase 1 — the modules in `module-list.md`.**
Topbar with all indicators. ~~Base Center with Overview, Appearance,
Displays & Hardware, and Security & Updates~~ (removed). `sysd` with `Host`, `Packages` and
`Security`. `centaur-settingsd`.

**Phase 2 — a complete desktop.**
`centaur-notifyd`, `centaur-launcher`, `centaur-bg`, `centaur-portald`; the
Network, Bluetooth, Sound and Power pages; `Firewall` and `Services`.

**Phase 3 — breadth.**
sway backend; internationalisation; packaging for all four distro families;
visual-regression baseline lock.

---

## 12. Build prerequisites

Verified on this machine on 2026-09-24: GTK4 4.22.5, Wayland 1.26.0,
GLib 2.88.3, Ninja 1.13.2 and GCC 16.2.1 are present. **`valac`, `meson`,
`gtk4-layer-shell` and the wlroots development packages are not.** Installing
them is the first step of Phase 0.

Package names vary between releases; treat these as a starting point.

| Distro | Packages |
|---|---|
| Arch | `vala meson ninja gtk4 gtk4-layer-shell wayland-protocols polkit libnm upower wireplumber` |
| Debian | `valac meson ninja-build libgtk-4-dev libgtk4-layer-shell-dev libwayland-dev wayland-protocols libpolkit-gobject-1-dev libnm-dev libupower-glib-dev libwireplumber-0.5-dev` |
| Fedora | `vala meson ninja-build gtk4-devel gtk4-layer-shell-devel wayland-devel wayland-protocols-devel polkit-devel NetworkManager-libnm-devel upower-devel wireplumber-devel` |
| openSUSE | `vala meson ninja gtk4-devel gtk4-layer-shell-devel wayland-devel wayland-protocols-devel polkit-devel libnm-devel libupower-glib-devel wireplumber-devel` |

**Arch Linux is the installation target.** `packaging/arch/PKGBUILD` is the one
list of packages: `depends` (required at runtime, including `labwc` and
Xwayland), `makedepends` (build) and `optdepends` (optional). `install.sh` reads
those arrays and installs everything missing with
`pacman -S --needed --noconfirm`, optional packages included, except `sway` (an
alternative compositor) and `pipewire-pulse` where PulseAudio already runs.
NetworkManager is enabled only when no other network service is active. On
other distributions the table above lists build equivalents, but nothing
installs them.

---

## 13. Decisions and their reasons

| Decision | Reason | Cost accepted |
|---|---|---|
| Shell on an existing compositor | Fastest path to a usable desktop; a compositor is its own multi-month subsystem | Inherits the host compositor's limits |
| Vala everywhere, C when forced | Honours "C is shipped" since valac emits C, without GObject boilerplate | A `valac` build dependency |
| One binary per module | Topbar stays tiny all session; crash isolation; restart one module while developing | IPC surface to define |
| One system daemon + distro backends | UI never learns a distro name and never runs as root | An API to write and version |
| GSettings as the store | Schemas, typing and change notification for free | Tied to dconf |
| Pure GTK4, no libadwaita | The design language is custom; libadwaita's styling would be overridden anyway | Some widgets written by hand |
| `wlr-output-management` for displays | Both targets implement it; no config-file rewriting for the most-changed setting | Excludes non-wlroots compositors |
| Indicators compiled in, layout data-driven | Reorderable without maintaining a plugin ABI | Adding an indicator needs a rebuild |
| Tokens as the single styling source | Three modes × eight accents cannot be hand-written | A generation step in the build |

---

## 14. Open questions

- ~~Whether `centaur-bg` stays a separate process or folds into `settingsd`~~ —
  settled 2026-09-24: separate and tiny. It supervises swaybg, which does the
  drawing, so `settingsd` never owns a renderer process.
- Whether the launcher subsumes a "run command" entry or stays application-only.
- Which visual-diff tolerance keeps the Phase 3 baseline stable across font
  versions — to be set empirically when the baseline is locked.
