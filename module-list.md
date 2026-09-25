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
workspaces, taskbar, focused-window, network, volume, battery, clock,
notifications, power. Resident all session; budget under 40 MB RSS.

**02. base center** — *removed*
The settings manager was removed from the project on 2026-09-24. Settings are
GSettings keys under `/org/centaur/`, changed with `gsettings`; settingsd still
applies them.

**03. launcher** — *Phase 2*
The START menu and application search. Spawned on demand, exits on close.

**13. displays** — *added 2026-09-24*
Display configuration: arrangement by drag-and-snap, resolution, refresh rate,
scale, orientation, enable/disable per monitor. Talks
`wlr-output-management-unstable-v1` (labwc, sway). Every change is tested,
applied, and reverted after 15 s unless kept. Kept layouts are saved to
`~/.config/centaur/displays.json` and restored at login and on hotplug by
`centaur-settingsd`. Spawned on demand, exits on close.

**14. screenshot** — *added 2026-09-25*
`centaur-screenshot`: whole screen, one display (multi-monitor only) or a
dragged area, with an optional delay. Captured by grim, regions chosen with
slurp (outlined in the accent colour), saved to `~/Pictures/Screenshots` and
copied to the clipboard with wl-copy. A layer-shell card under the topbar
confirms each shot with a thumbnail, Open and Show in Folder, without taking
keyboard focus. Bound to Print, Shift+Print and Super+Shift+S in labwc's
rc.xml, and in the desktop menu.

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

**08. centaur-bg** — *done 2026-09-24*
Wallpaper. A headless process started by the session that turns
`org.centaur.appearance` (`wallpaper`, `wallpaper-mode`, `background-color`)
into one supervised swaybg, swapped without a flash on every change. Chosen
with **centaur-background** ("Background" in the launcher): preview, the
token-generated Centaur wallpapers plus system and user ones, Add Picture
(copied to `~/.local/share/backgrounds`), position mode and colour.

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
