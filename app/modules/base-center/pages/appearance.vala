namespace Centaur.BaseCenter {

    /**
     * Appearance & Theming.
     *
     * Writes GSettings keys and nothing else. centaur-settingsd is what turns a
     * key into a rewritten compositor config or a gtk settings.ini; this page
     * never touches either, which is why changing the accent here also changes
     * it in the topbar without the two modules knowing about each other.
     */
    public class AppearancePage : Object, Page {

        private const string[] ACCENTS = {
            "emerald", "blue", "cyan", "purple",
            "amber", "orange", "slate", "crimson",
        };

        private const string[] ACCENT_LABELS = {
            "Emerald", "Blue", "Cyan", "Purple",
            "Amber", "Orange", "Slate", "Crimson",
        };

        private Core.Config config = Core.Config.get_default ();
        private Ui.Row[] schedule_rows = {};
        private Compositor.Backend compositor;

        public AppearancePage () {
            this.compositor = Compositor.Detect.create ();
        }

        public string id { owned get { return "appearance"; } }
        public string title { owned get { return "Appearance"; } }
        public string icon { owned get { return "applications-graphics-symbolic"; } }
        public string category { owned get { return CATEGORY_SYSTEM; } }

        public string[] keywords {
            owned get {
                return { "theme", "colour", "color", "dark", "light", "accent",
                         "font", "cursor", "icon", "wallpaper", "titlebar",
                         "window", "animation", "appearance", "style" };
            }
        }

        public Gtk.Widget create_widget () {
            var box = Layout.page_box ();

            box.append (Layout.heading ("Appearance & Style"));
            box.append (build_colour_card ());
            box.append (build_accent_card ());
            box.append (build_typography_card ());
            box.append (build_compositor_card ());

            return Layout.scroller (box);
        }

        private Gtk.Widget build_colour_card () {
            var card = new Ui.Card ("Colour mode");

            var row = new Ui.ComboRow (
                "Palette",
                { "auto", "dark", "pure-dark", "light" },
                { "Auto (scheduled)", "Dark", "Pure Dark (OLED)", "Light" },
                "Pure Dark uses a true black background, which saves power on "
                + "OLED panels");
            row.bind_setting (config.appearance, "colour-mode");
            card.add (row);

            var sunrise = new Ui.Row ("Switch to light at");
            var sunrise_entry = new Gtk.Entry () { width_chars = 6 };
            config.appearance.bind ("auto-sunrise", sunrise_entry, "text",
                                    SettingsBindFlags.DEFAULT);
            sunrise.set_suffix (sunrise_entry);
            card.add (sunrise);

            var sunset = new Ui.Row ("Switch to dark at");
            var sunset_entry = new Gtk.Entry () { width_chars = 6 };
            config.appearance.bind ("auto-sunset", sunset_entry, "text",
                                    SettingsBindFlags.DEFAULT);
            sunset.set_suffix (sunset_entry);
            card.add (sunset);

            // The schedule is meaningless unless the mode is Auto, so it goes
            // insensitive rather than sitting there inert and accepting edits
            // that will never take effect.
            schedule_rows = { sunrise, sunset };
            config.appearance.changed["colour-mode"].connect (() => update_schedule_sensitivity ());
            update_schedule_sensitivity ();

            return card;
        }

        private void update_schedule_sensitivity () {
            var is_auto = config.appearance.get_string ("colour-mode") == "auto";
            foreach (var row in schedule_rows) {
                row.sensitive = is_auto;
            }
        }

        private Gtk.Widget build_accent_card () {
            var card = new Ui.Card ("Accent colour");

            var grid = new Gtk.FlowBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                max_children_per_line = 8,
                min_children_per_line = 4,
                margin_top = 8,
                row_spacing = 8,
                column_spacing = 8,
            };

            for (var i = 0; i < ACCENTS.length; i++) {
                grid.append (accent_button (ACCENTS[i], ACCENT_LABELS[i]));
            }

            card.add (grid);
            return card;
        }

        /**
         * One accent swatch.
         *
         * The label is not decoration: eight colour squares with no names are
         * unusable for a colourblind user, and unsearchable for everyone.
         */
        private Gtk.Widget accent_button (string accent, string label) {
            var button = new Gtk.ToggleButton () {
                active = config.appearance.get_string ("accent") == accent,
            };
            button.add_css_class ("flat");

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);

            var swatch = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                width_request = 40,
                height_request = 24,
            };
            swatch.add_css_class ("centaur-accent-swatch");
            swatch.add_css_class (@"accent-$accent");
            box.append (swatch);

            box.append (new Gtk.Label (label) { });
            button.set_child (box);

            button.toggled.connect (() => {
                if (button.active) {
                    config.appearance.set_string ("accent", accent);
                }
            });

            config.appearance.changed["accent"].connect (() => {
                button.active = config.appearance.get_string ("accent") == accent;
            });

            return button;
        }

        private Gtk.Widget build_typography_card () {
            var card = new Ui.Card ("Typography & pointer");

            var ui_font = new Ui.Row ("Interface font");
            ui_font.set_suffix (font_button ("font-ui"));
            card.add (ui_font);

            var mono_font = new Ui.Row ("Monospace font",
                                        "Used for terminals, versions and paths");
            mono_font.set_suffix (font_button ("font-mono"));
            card.add (mono_font);

            var icons = new Ui.Row ("Icon theme");
            var icons_entry = new Gtk.Entry () { width_chars = 18 };
            config.appearance.bind ("icon-theme", icons_entry, "text",
                                    SettingsBindFlags.DEFAULT);
            icons.set_suffix (icons_entry);
            card.add (icons);

            var cursor_size = new Ui.SliderRow ("Pointer size", 16, 96, 8, "px");
            cursor_size.bind_setting (config.appearance, "cursor-size");
            card.add (cursor_size);

            return card;
        }

        /**
         * A font chooser bound to a string key.
         *
         * Not settings.bind(): the button's font-desc is a
         * Pango.FontDescription and the key is a string, so GSettings would
         * refuse the binding at runtime. The conversion has to be explicit.
         */
        private Gtk.Widget font_button (string key) {
            var button = new Gtk.FontDialogButton (new Gtk.FontDialog ());
            button.set_font_desc (
                Pango.FontDescription.from_string (config.appearance.get_string (key)));

            button.notify["font-desc"].connect (() => {
                var desc = button.get_font_desc ();
                if (desc == null) {
                    return;
                }
                var text = desc.to_string ();
                if (config.appearance.get_string (key) != text) {
                    config.appearance.set_string (key, text);
                }
            });

            config.appearance.changed[key].connect (() => {
                button.set_font_desc (
                    Pango.FontDescription.from_string (config.appearance.get_string (key)));
            });

            return button;
        }

        /**
         * Window behaviour, gated by what the running compositor can do.
         *
         * A control the compositor cannot honour is shown disabled with the
         * reason, never hidden and never live-but-useless. This is the
         * Capabilities mechanism reaching the UI.
         */
        private Gtk.Widget build_compositor_card () {
            var capabilities = compositor.capabilities;
            var card = new Ui.Card (@"Window behaviour · $(compositor.name)");

            var placement = new Ui.ComboRow (
                "New window placement",
                { "cursor", "center", "cascade", "automatic" },
                { "Under the pointer", "Centred", "Cascade", "Automatic" });
            if (capabilities.window_placement) {
                placement.bind_setting (config.compositor, "window-placement");
            } else {
                placement.set_unavailable (@"$(compositor.name) decides this itself");
            }
            card.add (placement);

            var titlebar = new Ui.ComboRow (
                "Titlebar buttons",
                { "right", "left" },
                { "Right side", "Left side" });
            if (capabilities.titlebar_buttons) {
                titlebar.bind_setting (config.compositor, "titlebar-side");
            } else {
                titlebar.set_unavailable (@"$(compositor.name) draws no titlebars");
            }
            card.add (titlebar);

            var animation = new Ui.SliderRow (
                "Transition duration", 0, 1000, 50, "ms",
                "How long window open and close animations take; 0 disables them");
            if (capabilities.animation_duration) {
                animation.bind_setting (config.compositor, "animation-duration");
            } else {
                animation.set_unavailable (@"$(compositor.name) does not animate windows");
            }
            card.add (animation);

            if (!capabilities.workspaces) {
                var note = new Ui.Row (
                    "Workspaces",
                    "The topbar's workspace pager needs a compositor that reports "
                    + "workspaces. A sway session has this today.");
                note.set_unavailable ("not reported by " + compositor.name);
                card.add (note);
            }

            return card;
        }
    }
}
