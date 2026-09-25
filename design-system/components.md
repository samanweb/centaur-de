# Centaur DE — Component Specifications

The widgets in `libcentaur-ui`, their style classes, their states, and the
tokens each consumes. Rules live in
[`templates/components.css.in`](templates/components.css.in); this document is
what a widget author reads before writing one.

Conventions:

- Every class is prefixed `centaur-`, except where a bare GTK node name is
  styled directly (`switch`, `scale`, `button`, `popover`).
- States use GTK pseudo-classes: `:hover`, `:active`, `:checked`, `:selected`,
  `:disabled`, `:focus-visible`.
- **Focus is never removed.** `*:focus-visible` draws a 2px accent ring at 2px
  offset. A widget that suppresses it must draw its own.

---

## Foundations

### Typography

| Class | Size | Weight | Use |
|---|---|---|---|
| `.title-lg` | 20px | 600 | Page title ("System Overview") |
| `.title` | 16px | 600 | Card group heading |
| `.centaur-card-header` | 14px | 600 | Card title |
| *(default)* | 13px | 400 | Body, row titles |
| `.centaur-row-subtitle` | 12px | 400 | Row description, `text.muted` |
| `.caption` | 11px | 400 | Metadata, `text.muted` |
| `.section-heading` | 11px | 600 | Sidebar group label, uppercase, 0.06em tracking |

`.mono` switches to the mono family. Use it for anything the user might copy or
compare character by character: package versions, device names, IP addresses,
the focused-window title. Do not use it for prose.

### Colour roles

| Role | Token | Meaning |
|---|---|---|
| Page background | `surface.window` | |
| Sidebar | `surface.sidebar` | |
| Card | `surface.card` | Content grouping |
| Inner block | `surface.raised` | Stat tiles inside a card |
| Popover, tooltip | `surface.overlay` | |
| Primary text | `text.primary` | |
| Supporting text | `text.secondary` | |
| De-emphasised | `text.muted` | Captions only — never a label that carries meaning alone |
| Unavailable | `text.disabled` | |

Status colours (`success`, `warning`, `danger`, `info`) are **independent of the
accent** so a user selecting the crimson accent does not make every success
state red.

---

## Topbar (module 01)

### `.centaur-topbar`
Root layer-shell surface. `surface.topbar`, hairline bottom border, min-height
32px, 4px side padding. Set in `font.family-ui` (Inter, falling back to
Adwaita Sans) at 12px/500 with tabular figures (`tnum`), so the clock and
percentages never shift the bar as digits change.

### `.centaur-indicator`
Base class for every topbar item: a 24px-high pill inside the 32px bar, 8px
horizontal padding, `radius.sm`, `text.secondary`, 8px between icon and text.
`:hover` raises to `surface.card-hover` and lifts text to `text.primary`; a
menubutton indicator stays lit while its menu is open. `.warning` and `.danger`
tint it with the status colours — reinforcing a state the icon already shows.

Icons are 16px symbolic, looked up by their freedesktop names
(`network-wireless-signal-*`, `audio-volume-*`, `battery-level-*`, …) so the
user's icon theme restyles the bar; Adwaita is the fallback. The one icon
Centaur ships is the launcher mark, `centaur-start-symbolic`, drawn in
`accent.base`.

| Indicator | In the bar | In the tooltip |
|---|---|---|
| launcher | mark | — |
| taskbar | one icon per running app | app name, window title or count |
| network | link type / Wi-Fi strength | connection name, signal |
| volume | level icon (click mutes, scroll steps 5%) | percentage |
| battery | level icon + percentage | time remaining |
| clock | `clock-format`, `text.primary`; click opens a calendar | full date |
| power | shutdown icon | — |

**Indicators build their popover on first click, never at construction.** This
is a resource requirement from `architecture.md` §4.1, not a style note.

### `.centaur-workspace`
One per workspace. Three states, and the distinction must survive a
monochrome screenshot:

| State | Appearance |
|---|---|
| empty | `text.muted`, no background |
| `.occupied` | `text.secondary` |
| `.active` | `accent.bg` fill, `accent.base` text, weight 600 |

### `.centaur-task`
One per running application, windows grouped by app id, in opening order. An
18px full-colour app icon in a 24px pill. Three states, readable without
colour:

| State | Appearance |
|---|---|
| running | icon only |
| `.active` | `surface.card-hover` fill, 2px `accent.base` underline |
| `.minimized` (every window) | icon at 50% opacity |

### `calendar.centaur-calendar`
The clock's popover: a full-date heading at 13px/600, then a transparent
`GtkCalendar` with 32px day cells. Today is `accent.base` at weight 600; the
selected day is an `accent.base` fill with `accent.ink` text; other-month days
are `text.disabled`. It always opens on today.

### `.centaur-focused-window`
The window title only, `font.family-ui` at weight 400, `text.secondary`, no
hover fill. Ellipsises at the end at 60 characters; never wraps. The app id is
in the tooltip.

### labwc: titlebars, desktop menu, window menu, window switcher
labwc draws these itself, so they are themed through a generated labwc theme,
`Centaur-<accent>-<palette>` (24 of them, installed in `/usr/share/themes`),
selected by centaur-settingsd in `rc.xml` as palette and accent change.

| Element | Tokens |
|---|---|
| Menu | `surface.overlay`, hairline `border.default`, `text.primary`, 12/7px item padding, 200–320px wide |
| Highlighted item | `accent.base` mixed 20% over `surface.overlay`, `text.primary` (contrast-gated at 4.5:1) |
| Separator | `border.subtle`, 8px inset |
| Titlebar | `surface.sidebar` active / `surface.window` inactive, like the GTK headerbar; buttons `text.secondary` with a `radius.sm` hover |
| Window switcher | `surface.overlay`, active item with a 2px `accent.base` border |
| Snapping overlay | `accent.base` at 25% |

`rc.xml` also sets `font-ui` (Inter) for titles (bold), menus and the switcher,
10px window corners, drop shadows, and text-only menus: labwc draws menu icons
in their own colours, so symbolic icons would be near-black on a dark menu.
labwc menus have square corners; it has no setting for them.

### Screenshot: `.centaur-screenshot-mode`, `.centaur-screenshot-card`
Mode toggles are 96px-wide buttons with a 24px icon over the label;
`:checked` takes `accent.bg`, an `accent.base` border and accent text. The
confirmation card is a layer-shell overlay 40px below the top edge (clear of
the topbar): `surface.overlay`, hairline `border.default`, `radius.lg`, a
280px thumbnail in `radius.sm`, 14px/600 heading. `.danger` borders it in
`status.danger`. Its window is fully transparent, or GTK's theme would draw a
light box behind the rounded card.

### Button labels inherit
`button label, button image { color: inherit }`. Without it, the base `label`
rule gave every accent button `text.primary` instead of its contrast-chosen
`accent.ink`.

### `.centaur-wallpaper-preview` / `.centaur-wallpaper`
The Background window. The preview is the first monitor's shape with
`radius.lg`, the background colour painted under the picture exactly as swaybg
shows it around 'fit' and 'center'. Library tiles are 224×126, `radius.sm`,
cropped to cover. Selection is a 2px `accent.base` ring *outside* the picture,
never a tint over it: the picture is what is being judged.

### Wallpapers
`app/data/backgrounds/centaur-<accent>-<palette>.svg`, generated from the
tokens: a `surface.window`→`surface.card` diagonal, an accent glow top-right,
an `accent.dim` ember bottom-left and faint concentric rings. The default is
`centaur-emerald-dark.svg`.

### Buttons and title bars against GTK's theme
GTK's built-in theme paints buttons (and the switch knob) with a
`background-image` gradient in every state, drawn over `background-color`.
The button rules reset it, or no token colour is ever visible. `headerbar` is
styled from the tokens, and `Ui.Theme` sets `gtk-application-prefer-dark-theme`
from the resolved palette so unstyled widgets follow the palette too.

### `.centaur-display-canvas` / `.centaur-display-tile`
The arrangement in Displays. The canvas is `surface.window` with a hairline
`border.subtle` and `radius.md`; each monitor is a tile drawn to scale in
`surface.raised` with a `border.strong` hairline and `radius.sm`, showing the
connector name (12px/600) and resolution (caption). `.selected` takes a 2px
`accent.base` border and an `accent.bg` fill. Tiles snap edge-to-edge when
dropped, never overlapping.

### `.centaur-topbar-menu` / `.centaur-menu-item`
Topbar popovers drop the arrow and use 4px padding. A menu item is a flat
32px row, icon then label, 12px apart; `.danger` (Power Off) takes
`status.danger` text and a `status.danger-bg` hover.

### `.centaur-badge`
Notification count. `accent.base` fill, `accent.ink` text, pill radius, 11px/600.
Hidden at zero — never renders "0".

---

## Cards and rows

### `.centaur-card`
`surface.card`, hairline `border.subtle`, `radius.lg`, 16px padding.

Modifiers: `.accent` (border `accent.dim`) marks the card the page is about;
`.danger` (border `status.danger`) marks a destructive region. Use at most one
per page — two accent cards means neither is emphasised.

### `.centaur-row`
40px min-height, 8px vertical padding. Consecutive rows get a hairline
`border.subtle` top border via `+`, so the first row needs no special case.

Structure: title (`.centaur-row-title`, weight 500), optional subtitle
(`.centaur-row-subtitle`), control at the end.

Row variants — `ToggleRow`, `SliderRow`, `ComboRow` — differ only in the trailing
control. They share this class and layout.

### Unavailable rows
A setting the running system cannot support gets `.centaur-unavailable`
(`text.disabled`) and a `.centaur-chip.info` reading "unavailable on this
system". It is **shown and explained, never hidden** — `architecture.md` §9. The
same applies to compositor features `Capabilities` reports as absent.

---

## Controls

### `switch`
Track `control.track`, `:checked` becomes `accent.base`, `:disabled` becomes
`control.track-disabled`. Thumb is `control.thumb`, pill radius. 180ms standard
easing.

### `scale`
Trough `control.track`, highlight `accent.base`, thumb `control.thumb` at 16px.
All pill radius.

A slider that maps to a non-obvious unit shows its value in a `.caption.mono`
beside the label — the Displays page's colour temperature, for example, is
meaningless without "3400K".

### `button`

| Class | Fill | Text | Use |
|---|---|---|---|
| *(default)* | `control.fill` | `text.primary` | Secondary action |
| `.accent` | `accent.base` | `accent.ink` | The page's primary action |
| `.danger` | `status.danger-bg` | `status.danger` | Destructive; tinted, not solid |
| `.flat` | transparent | `text.secondary` | Toolbar, icon-only |

`.pill` swaps to pill radius for filter chips.

`.danger` is deliberately tinted rather than a solid red block: a solid fill
draws the eye to the most destructive control on the page, which is backwards.

---

## Data display

### `.centaur-stat-tile`
`surface.raised`, `radius.md`, 12px padding. `.centaur-stat-value` is 28px/600
mono; `.centaur-stat-label` is 11px `text.muted`.

Mono matters here — a column of proportional figures will not align, and these
are read as a column.

### `MeterRing`
The circular gauge (CPU utilisation, battery). CSS supplies colour only; the arc
is drawn in `libcentaur-ui`.

Geometry, fixed so every ring in the app matches:

- stroke 6px, round cap
- sweep starts at −90° (12 o'clock), clockwise
- track is a full circle in the widget's own colour at 18% alpha, derived in
  code rather than from a CSS class: the ring is one drawing area, so a second
  class could not reach it
- value label centred, 20px/600 mono

Colour thresholds: `accent.base` by default, `.warning` above 80%,
`.danger` above 95%. **A ring must never be the only indicator of a problem** —
pair it with a chip, since the colour change alone fails for colourblind users
and in a monochrome screenshot.

### `progressbar`
Trough `control.track`, progress `accent.base`, pill radius. Used for Job
progress (`architecture.md` §6.3). Indeterminate until the backend reports a
first percentage — never fake a 0%.

---

## Status chips

`.centaur-chip` plus one of `.success`, `.warning`, `.danger`, `.info`,
`.accent`. Pill radius, 11px/500, tinted background with matching text.

**A chip always carries a word.** Colour is reinforcement, not the message: a
green dot alone does not tell a colourblind user the firewall is on.

---

## Surfaces

### `popover > contents`
`surface.overlay`, hairline `border.default`, `radius.lg`, 8px padding.

### `tooltip`
`surface.overlay`, `radius.sm`, 12px. Tooltips explain; they never carry
information available nowhere else.

### `separator`
`border.subtle`, 1px. Prefer row borders and card grouping over separators —
the screenshots use very few.

---

## Motion

| Token | Duration | Use |
|---|---|---|
| `motion.duration-fast` | 120ms | Hover, background colour |
| `motion.duration-base` | 180ms | Switch, checkbox, state change |
| `motion.duration-slow` | 260ms | Popover, page transition |

Easing is `motion.easing-standard` — `cubic-bezier(0.2, 0, 0, 1)` — for
everything that starts and stops on screen.

Nothing animates for longer than 260ms. The Appearance page's compositor
transition setting controls *window* animations in the host compositor; it does
not apply to widgets.
