# Task log — Bug hunt across the project

**Date:** 2026-09-24
**Task:** "check any bugs in this project if find it fix it"
**Outcome:** 18 defects found by inspection and fixed. All validators still pass.

Still no compiler: `valac` and `meson` remain absent, so this was a reading
pass, not a build. Everything below was found by reading the code against the
Vala, GLib, GTK4 and D-Bus semantics it depends on.

## Would have been wrong at runtime

**1. sway replies were read into a throwaway copy.** `read_message` did
`var slice = body[0:length]` and read into `slice`. A Vala array slice assigned
to a local is a *copy*, so the socket data landed in the copy and `body` stayed
zeroed — every sway reply would have parsed as an empty string, and the
workspace pager and window title would silently never populate. Replaced the
slice with length manipulation on the one buffer.

**2. `pacman -Sy` in CheckUpdates.** Syncing the package database without
upgrading in the same transaction is the classic Arch partial-upgrade hazard,
and a settings window is the last place that should do it silently. Now uses
`checkupdates` from pacman-contrib, which syncs into a temporary database, and
degrades to reading the local database when that is absent. `pacman-contrib`
added to the package's depends. **This one mattered because the target is Arch.**

**3. Update list stacked duplicates.** `refresh_updates()` appended rows
straight onto the card and is called again whenever `updates_changed` fires or
an install finishes. After one upgrade the page would show every package twice,
the second time with versions it no longer had. The list now has its own
container that is emptied before refill.

**4. Integer settings could not bind to sliders.** `SliderRow.bind_setting`
bound an int key to `Gtk.Adjustment.value`, a double. GSettings refuses a
binding whose types disagree, so `cursor-size` and `animation-duration` — the
only two settings this row type exists for — would both have failed. Mapped
explicitly with rounding.

**5. Content width request blocked window resizing.** `set_size_request` is a
minimum, not a maximum. With a 220px sidebar and `hscrollbar_policy NEVER` it
made the window unable to shrink below ~1320px and clipped cards at the default
1100px. Removed, and the unimplemented max-width is now documented as needing a
custom `LayoutManager` (there is no AdwClamp in a libadwaita-free build).

## Object lifetime — five instances of one mistake

Widgets subscribing to objects that outlive them, with cleanup in a destructor
that can never run because the closure itself holds the reference. On monitor
unplug the bar is destroyed and the handlers keep firing on it.

- `ClockIndicator` — timer kept ticking after its bar was gone
- `VolumeIndicator` — leaked a `pactl subscribe` child process
- `Bar` — GSettings handlers kept repopulating a destroyed window
- `WorkspacesIndicator`, `FocusedWindowIndicator` — compositor subscriptions

All five now use `map`/`unmap`, which is the GTK4 hook that actually fires. As a
side effect the clock and the audio subscription also go quiet while hidden.

**6. `Theme.parsing_error` was connected inside `reload()`**, so every accent or
mode change added another handler: ten changes, ten duplicate log lines per CSS
error, and ten closures never released. Moved to the constructor.

## Would not have compiled

**7. `foreach` over `GLib.GenericSet`** — it has no iterator. Replaced with an
array and a linear scan; monitor counts are tiny.

**8. Method references on `Settings::changed`** (7 sites). A lambda may take
fewer parameters than its signal, but a *method reference* is checked strictly
against the delegate signature, and `changed` carries a `key` argument. Wrapped
in lambdas.

**9. String literals nested inside `$(...)` in template strings** (5 sites, in
`detect.vala` and `applier.vala`). Hoisted into locals — safer and clearer.

**10. `Posix.Signal` passed where an `int` is expected** (8 sites across
`Unix.signal_add` and `Subprocess.send_signal`). Added explicit casts.

**11. `va_list` forwarded through a helper** in `Core.Log`. Each wrapper now
calls `GLib.logv` directly, the standard idiom.

**12. `public new void add`** on `Ui.Card` hid nothing — GTK4's `Gtk.Box` has no
`add()`, that was GTK3's `Container.add`. Dropped the `new`, and added the
`clear()` that fix 3 needed.

**13. Empty `{}` array literal** passed to `start_update` with no element type
to infer. Made `new string[0]`.

**14. Unchecked numeric conversions** — `format_size_full` takes `uint64`,
`Variant.int64` was handed a `uint`. Cast both, and guarded `format_size`
against negatives.

**15. `string.to_utf8()` element comparisons** against char literals in package
name validation. Indexing the string yields a `char` directly.

## Design defects

**16. `Toplevel` was a nullable struct crossing an interface boundary** — a Vala
corner that works until it does not. Now a class, which makes null handling
ordinary. `Workspace` and `Capabilities` stay structs; neither is ever nullable.

**17. The distro switch lived in the wrong place.** `PackagesService.refresh_argv`
switched on `backend.name`, which is exactly the distro knowledge
`architecture.md` §6.1 says must stop at the backend boundary. `refresh_argv()`
is now on the `PackageBackend` interface, implemented by each of the four.

**18. Dead code** — a no-op `set_size_request(-1, -1)` and a clamp box that
clamped nothing, both removed with fix 5.

## Verification

Unchanged and still passing: schema compiles, XML well-formed, desktop files
valid, shellcheck clean, PKGBUILD parses, 29 generated files current, 93/93
contrast. Added a crude brace-balance check across all 41 Vala files — all
balanced.

**Still not verified: the Vala compiles.** These fixes remove defects I could
reason about; they do not substitute for a build.

## What I would look at next

The remaining risk concentrates in three places, none of which reading can
settle: the async D-Bus method signatures in `daemons/sysd`, the struct
property `Capabilities` on an interface, and whether `gtk4-layer-shell`'s VAPI
namespace matches `GtkLayerShell` on the target.
