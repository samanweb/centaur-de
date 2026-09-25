# Task log — Build deprecation warnings

**Date:** 2026-09-25
**Task:** "look in to this warnings and how to resolve these issues"
(from the output of a real `./install.sh` run)

## The three warnings

1. **`Gtk.StyleContext` deprecated since 4.10** (theme.vala). This is a false
   positive. The function called, `gtk_style_context_add_provider_for_display`,
   is `GDK_AVAILABLE_IN_ALL` in `gtkstyleprovider.h`, and GTK has no
   replacement for installing a display-wide provider. Only the
   `GtkStyleContext` class is deprecated, and the Vala binding hangs this
   function off it.
   **Fix:** bind the C function directly with `extern` and `[CCode (cname …)]`.

2. **`Gtk.Settings.gtk_application_prefer_dark_theme` deprecated since 4.20**
   (theme.vala). GTK 4.20 replaced it with `Gtk.Settings:gtk-interface-color-scheme`.
   **Fix:** use `InterfaceColorScheme.DARK` / `LIGHT` under `#if GTK_4_20`, and
   the old boolean otherwise.

3. **`Gtk.Calendar.select_day` deprecated since 4.20** (clock.vala). Replaced
   by `set_date`.
   **Fix:** the same `#if GTK_4_20` switch.

`app/meson.build` passes `--define=GTK_4_20` to valac when the gtk4 found is
4.20 or newer, so current systems use the new APIs and GTK 4.12, the minimum,
still builds.

## Verified

- A clean build on GTK 4.22 has **0 warnings**, and both tests pass.
- Compiling without the define (the pre-4.20 branch) succeeds. The generated
  C calls `select_day` and `gtk-application-prefer-dark-theme` there, and
  `set_date` and `gtk-interface-color-scheme` in the real build.
- On GTK 4.22, the new setting switches GTK's built-in theme: an unstyled
  entry's text is `#000000` under LIGHT and `#ffffff` under DARK, the same
  effect as the old property.
