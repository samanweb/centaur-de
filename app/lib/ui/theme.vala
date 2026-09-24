namespace Centaur.Ui {

    /**
     * Loads the generated stylesheets and keeps them in step with GSettings.
     *
     * The load order is a contract set by the design system: the accent block
     * must come first, because tokens-<palette>.css derives its tints with
     * alpha(@centaur_accent_base, ...) and @define-color resolves in the order
     * it is seen. All three sheets go into one provider so a reload is atomic.
     */
    public class Theme : Object {

        private const string FALLBACK_ACCENT = "emerald";
        private const string FALLBACK_PALETTE = "dark";

        private static Theme? instance = null;

        private Gtk.CssProvider provider;
        private Core.Config config;
        private uint reload_source = 0;
        private uint auto_source = 0;

        public static void init () {
            if (instance == null) {
                instance = new Theme ();
            }
        }

        private Theme () {
            this.config = Core.Config.get_default ();
            this.provider = new Gtk.CssProvider ();

            var display = Gdk.Display.get_default ();
            if (display == null) {
                Core.Log.warn ("no display; stylesheets not loaded");
                return;
            }

            Gtk.StyleContext.add_provider_for_display (
                display, this.provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

            // Connected once. GTK reports parse errors through a signal rather
            // than an exception, so without this a typo in the template is
            // invisible -- but connecting it inside reload() would add a handler
            // per accent change.
            provider.parsing_error.connect ((section, e) => {
                Core.Log.error ("CSS parse error at %s: %s",
                                section.to_string (), e.message);
            });

            reload ();

            // Both keys change the accent block, so both trigger a reload.
            config.appearance.changed["colour-mode"].connect (() => queue_reload ());
            config.appearance.changed["accent"].connect (() => queue_reload ());
            config.appearance.changed["auto-sunrise"].connect (() => schedule_auto_switch ());
            config.appearance.changed["auto-sunset"].connect (() => schedule_auto_switch ());

            schedule_auto_switch ();
        }

        /**
         * Under 'auto' the palette depends on the time, and no GSettings key
         * changes when the sun does. Each process schedules its own wake-up for
         * the next boundary rather than being told by a daemon: one timer per
         * process is cheaper than a signal, and nothing breaks if settingsd is
         * not running.
         */
        private void schedule_auto_switch () {
            if (auto_source != 0) {
                Source.remove (auto_source);
                auto_source = 0;
            }

            if (config.appearance.get_string ("colour-mode") != "auto") {
                return;
            }

            var seconds = config.seconds_until_palette_change ();
            auto_source = Timeout.add_seconds (seconds, () => {
                auto_source = 0;
                reload ();
                schedule_auto_switch ();
                return Source.REMOVE;
            });
        }

        /**
         * Coalesce bursts of key changes into one reload.
         *
         * Switching mode and accent together would otherwise rebuild the
         * provider twice and flash.
         */
        private void queue_reload () {
            if (reload_source != 0) {
                Source.remove (reload_source);
            }
            reload_source = Timeout.add (30, () => {
                reload_source = 0;
                reload ();
                return Source.REMOVE;
            });
        }

        private void reload () {
            var palette = config.resolved_palette ();
            var accent = config.appearance.get_string ("accent");

            var css = compose (palette, accent);
            if (css == null) {
                Core.Log.error ("no stylesheets found; the desktop will be unstyled");
                return;
            }

            provider.load_from_data (css.data);
            Core.Log.debug ("loaded palette=%s accent=%s", palette, accent);
        }

        /** Concatenates the three sheets in the order the contract requires. */
        private string? compose (string palette, string accent) {
            var dir = theme_dir ();
            if (dir == null) {
                return null;
            }

            var parts = new StringBuilder ();

            var accent_css = read (@"$dir/accents/$accent-$palette.css");
            if (accent_css == null) {
                // An unknown accent must not leave the desktop unstyled.
                Core.Log.warn ("unknown accent '%s'; falling back to %s",
                               accent, FALLBACK_ACCENT);
                accent_css = read (@"$dir/accents/$FALLBACK_ACCENT-$palette.css");
            }
            if (accent_css != null) {
                parts.append (accent_css);
            }

            var tokens = read (@"$dir/tokens-$palette.css");
            if (tokens == null) {
                tokens = read (@"$dir/tokens-$FALLBACK_PALETTE.css");
            }
            if (tokens != null) {
                parts.append (tokens);
            }

            var components = read (@"$dir/components.css");
            if (components != null) {
                parts.append (components);
            }

            return parts.len > 0 ? parts.str : null;
        }

        /**
         * Where the generated stylesheets live.
         *
         * CENTAUR_THEME_DIR first so the tree can be run without installing,
         * then the XDG data directories so a --prefix install is found without
         * compiling the path in.
         */
        private static string? theme_dir () {
            var env = Environment.get_variable ("CENTAUR_THEME_DIR");
            if (env != null && FileUtils.test (env, FileTest.IS_DIR)) {
                return env;
            }

            foreach (var data_dir in Environment.get_system_data_dirs ()) {
                var candidate = Path.build_filename (data_dir, "centaur", "themes");
                if (FileUtils.test (candidate, FileTest.IS_DIR)) {
                    return candidate;
                }
            }

            var fallback = "/usr/share/centaur/themes";
            return FileUtils.test (fallback, FileTest.IS_DIR) ? fallback : null;
        }

        private static string? read (string path) {
            string contents;
            try {
                if (!FileUtils.test (path, FileTest.EXISTS)) {
                    return null;
                }
                FileUtils.get_contents (path, out contents);
                return contents;
            } catch (FileError e) {
                Core.Log.warn ("cannot read %s: %s", path, e.message);
                return null;
            }
        }
    }
}
