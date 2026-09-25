# Task log — Screenshot tool

**Date:** 2026-09-25
**Task:** "Add appropriate tool to get screenshots to the desktop environment.
apply changes to the installer and project"

## Choice of tools

**grim** captures and **slurp** selects: the standard wlroots pair, about 46 KB
and 39 KB. labwc 0.20 offers both protocols grim uses
(`zwlr_screencopy_manager_v1` v3 and `ext_image_copy_capture_manager_v1`).
**wl-clipboard** is needed because on Wayland a clipboard dies with the
program that set it. Centaur owns the experience; the small tools do the
pixels, as swaybg does for the wallpaper.

## Built: `centaur-screenshot` (`app/modules/screenshot/`)

- **capture.vala:**
  - `--screen` runs grim on everything; `--display` runs `slurp -o`, then
    `grim -g`; `--area` runs `slurp`, then `grim -g`.
  - slurp is styled from the tokens: accent outline and a faint fill, a
    dimmed backdrop, the size shown while dragging, Inter.
  - Saves to `~/Pictures/Screenshots/Screenshot from <date time>.png` (the
    XDG Pictures directory; a second shot in the same second gets a suffix),
    then runs `wl-copy --type image/png`.
  - Escape during the selection cancels silently; a missing tool gives a
    message naming the pacman package.
- **window.vala:** the capture window: Area, Display (only with more than one
  monitor) and Screen as large toggles, a delay of none, 3, 5 or 10 s, and
  Take Screenshot. It hides itself and waits 350 ms for a repaint before
  capturing.
- **toast.vala:** the confirmation card.
  - A layer-shell OVERLAY surface at the top right, 40 px down (under the
    topbar), with keyboard mode NONE so it never takes focus.
  - A 280 px decoded thumbnail (click to open), Open and Show in Folder, and
    a close button.
  - Dismisses itself after 6 s, paused while the pointer is over it. A failure
    variant has a danger border.
- **main.vala:** a single-instance GtkApplication handling
  `--screen/--display/--area`; with no argument it opens the window. It holds
  the app while capturing.
- `Ui.Theme.accent_hex (palette)` is a new shared helper.

**labwc** (`LabwcBackend`):
- rc.xml gets `<keyboard><default />` plus Print → `--screen`,
  Shift+Print → `--area` and Super+Shift+S → the window. `<default />` is
  essential: without it labwc drops its built-in bindings, Alt+Tab included.
- The desktop menu gets "Take Screenshot…".

Also a launcher entry (`centaur-screenshot.desktop`) and a `screenshot` meson
option.

## Bugs found by rendering

1. **Oversized card (672×515).** A GtkPicture's size request is only a
   minimum, so the full screenshot sized the card. It now uses a decoded
   280 px thumbnail.
2. **White corners around the card.** GTK's built-in theme paints
   `window.background` and a shadow; both are now cleared on the card's
   window.
3. **Light text on accent buttons, everywhere.** The base `label` rule beat
   the colour labels should inherit from their button, so accent buttons
   showed `text.primary` instead of `accent.ink`. This affected Apply,
   Add Picture… and others. Fixed once with
   `button label, button image { color: inherit }`.

## Verified

- With stand-in grim, slurp and wl-copy on a nested headless labwc (real
  binary):
  - `--area`: slurp got the accent styling, grim `-g "10,20 300x200"` wrote
    the PNG, wl-copy received all 59,904 bytes, and the card stayed 6 s;
  - Escape: exited immediately with nothing saved;
  - `--screen`: grim ran without `-g`;
  - grim missing: the error card, with the install command.
- slurp's options and colour format were checked against slurp 1.5's `main.c`.
- The generated rc.xml and menu.xml are valid, and labwc 0.20.2 loaded them
  with no warnings.
- Renders of the window and both cards were reviewed after the fixes.
- Clean build with 0 warnings, tests pass, staged install;
  `./install.sh --check` now lists `grim slurp wl-clipboard` as required.

**Not tested:** real pixels from grim, since it is not installed yet; the
installer installs it.

## Installer / packaging

grim, slurp and wl-clipboard were added to the PKGBUILD's `depends`, so
`install.sh` installs them. Its closing message and the pacman message list
the shortcuts. Version 0.1.10 → 0.1.11.
