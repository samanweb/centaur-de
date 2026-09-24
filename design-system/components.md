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
32px, 12px base font.

### `.centaur-indicator`
Base class for every topbar item. 8px horizontal padding, `radius.sm`,
`text.secondary`. `:hover` raises to `surface.card-hover`; `.active` (popover
open) lifts text to `text.primary`.

**Indicators build their popover on first click, never at construction.** This
is a resource requirement from `architecture.md` §4.1, not a style note.

### `.centaur-workspace`
One per workspace. Three states, and the distinction must survive a
monochrome screenshot:

| State | Appearance |
|---|---|
| empty | `text.muted`, no background |
| `.occupied` | `text.secondary` |
| `.active` | `accent.bg` fill, `accent.base` text, weight 500 |

### `.centaur-focused-window`
Mono, 12px, `text.secondary`. Ellipsises at the end; never wraps.

### `.centaur-badge`
Notification count. `accent.base` fill, `accent.ink` text, pill radius, 11px/600.
Hidden at zero — never renders "0".

---

## Base Center shell (module 02)

### `.centaur-sidebar`
`surface.sidebar`, 220px, hairline right border, 8px padding.

### `.centaur-sidebar-row`
32px min-height, `radius.md`. `:selected` takes `accent.bg` with `accent.base`
text at weight 500 — matching the workspace pill, so selection reads the same
way in both modules.

### `entry.centaur-search`
`surface.card` fill, hairline `border.default`, `radius.md`. On `:focus` the
border becomes `accent.base`; the focus ring still draws.

### `.centaur-content`
Scrolling page region. `surface.window`, 24px padding. Content caps at 1100px
(`layout.content-max-width`) so cards do not stretch on ultrawide displays.

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
