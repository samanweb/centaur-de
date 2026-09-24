# Centaur DE — Module List

Index of every component in the application. Architecture and rationale live in
[architecture.md](architecture.md); phases are defined in its §11.

**Status at 0.1.0:** modules 01, 02, 04, 05, 09, 10, 11 and 12 are written but
not yet compiled — see [app/README.md](app/README.md). Modules 03, 06, 07 and 08
are not started.

## UI modules

**01. top bar** — *Phase 1*
Display icons and date and time like KDE or Gnome topbar.
`gtk4-layer-shell` panel on layer TOP, one per output. Indicators: launcher,
workspaces, quicklaunch, focused-window, network, volume, battery, clock,
notifications, power. Resident all session; budget under 40 MB RSS.

**02. base center** — *Phase 1*
Work as setting manager for update system configuration.
Sidebar + global search + card grid. Pages: Overview, Appearance,
Displays & Hardware, Security & Privacy, Network & Wi-Fi, Bluetooth,
Sound & Audio, Power & Battery. Spawned on demand, exits on close.

**03. launcher** — *Phase 2*
The START menu and application search. Spawned on demand, exits on close.

## Session services

**04. centaur-session** — *Phase 0*
Session entry point. Starts the host compositor and all services, supervises
them, restarts crashes with capped backoff.

**05. centaur-settingsd** — *Phase 1*
Watches configuration and applies it outward: compositor config, GTK theme and
font, cursor, accent CSS regeneration. Headless.

**06. centaur-notifyd** — *Phase 2*
`org.freedesktop.Notifications`. Exposes the unread count the topbar badge reads.

**07. centaur-portald** — *Phase 2*
`xdg-desktop-portal` backend, so sandboxed apps get Centaur's file chooser,
screenshot and settings.

**08. centaur-bg** — *Phase 2*
Wallpaper, drawn on the layer-shell background layer.

## Privileged

**09. centaur-sysd** — *Phase 1*
Root D-Bus service `org.centaur.System1`, polkit-gated per action, GLib/GIO only.
Distro backends for packages (pacman / apt / dnf / zypper), firewall, services,
disk encryption.

## Shared libraries

**10. libcentaur-core** — *Phase 0*
Configuration access, D-Bus client wrappers, distro detection, logging.

**11. libcentaur-ui** — *Phase 0*
The shared widgets: Card, ToggleRow, SliderRow, ComboRow, StatTile, MeterRing.
Consumes the tokens in [design-system/](design-system/) — see
[components.md](design-system/components.md) for each widget's classes, states
and tokens. Stylesheets are generated into `app/data/themes/`; no widget may
contain a literal colour or length.

**12. libcentaur-compositor** — *Phase 0*
`CompositorBackend` interface with labwc (reference) and sway backends, plus the
`Capabilities` model that drives feature availability in the UI.
