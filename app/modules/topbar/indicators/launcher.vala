namespace Centaur.Topbar {

    /**
     * The START button and its application list.
     *
     * The standalone centaur-launcher is Phase 2 work. Until it exists this
     * provides the same job from inside the bar, built on GLib.AppInfo so it
     * sees exactly the applications the rest of the desktop does.
     *
     * The list is built on first click, never at construction -- the bar is
     * resident all session and must not carry a parsed copy of every .desktop
     * file on the machine for a popover nobody has opened.
     */
    public class LauncherIndicator : Gtk.Box, Indicator {

        private Gtk.MenuButton button;
        private Gtk.SearchEntry search;
        private Gtk.ListBox results;
        private Gtk.Popover menu;
        private bool populated = false;
        private List<AppInfo> applications = new List<AppInfo> ();

        public string indicator_id { owned get { return "launcher"; } }

        public LauncherIndicator () {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

            // GtkMenuButton is final in GTK4, so the indicator holds one
            // rather than being one.
            button = new Gtk.MenuButton () {
                label = "START",
                tooltip_text = "Applications",
            };
            button.add_css_class ("centaur-indicator");
            button.add_css_class ("flat");
            append (button);

            search = new Gtk.SearchEntry () {
                placeholder_text = "Search applications",
                width_request = 260,
            };

            results = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.SINGLE,
            };
            results.add_css_class ("centaur-launcher-results");

            var scroller = new Gtk.ScrolledWindow () {
                child = results,
                height_request = 320,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
            };

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            box.append (search);
            box.append (scroller);

            menu = new Gtk.Popover () { child = box };
            button.popover = menu;

            search.search_changed.connect (() => filter (search.text));
            results.row_activated.connect (row => launch_row (row));

            // Enter launches the first match without leaving the keyboard.
            search.activate.connect (() => {
                var first = results.get_row_at_index (0);
                if (first != null) {
                    launch_row (first);
                }
            });

            menu.notify["visible"].connect (() => {
                if (menu.visible) {
                    populate ();
                    search.text = "";
                    search.grab_focus ();
                }
            });
        }

        private void populate () {
            if (populated) {
                return;
            }
            populated = true;

            foreach (var info in AppInfo.get_all ()) {
                if (info.should_show ()) {
                    applications.append (info);
                }
            }

            applications.sort ((a, b) => {
                return a.get_display_name ().collate (b.get_display_name ());
            });

            filter ("");
        }

        private void filter (string query) {
            Gtk.Widget? child;
            while ((child = results.get_first_child ()) != null) {
                results.remove (child);
            }

            var needle = query.down ().strip ();
            var shown = 0;

            foreach (var info in applications) {
                if (shown >= 50) {
                    break;  // a popover is not a directory listing
                }
                if (needle != "" && !matches (info, needle)) {
                    continue;
                }
                results.append (build_row (info));
                shown++;
            }
        }

        private static bool matches (AppInfo info, string needle) {
            if (needle in info.get_display_name ().down ()) {
                return true;
            }
            var description = info.get_description ();
            if (description != null && needle in description.down ()) {
                return true;
            }
            var executable = info.get_executable ();
            return executable != null && needle in executable.down ();
        }

        private Gtk.Widget build_row (AppInfo info) {
            var row = new Gtk.ListBoxRow ();
            row.set_data<AppInfo> ("app-info", info);

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);

            var icon = new Gtk.Image () { pixel_size = 20 };
            if (info.get_icon () != null) {
                icon.gicon = info.get_icon ();
            } else {
                icon.icon_name = "application-x-executable";
            }
            box.append (icon);

            var label = new Gtk.Label (info.get_display_name ()) {
                xalign = 0,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END,
            };
            box.append (label);

            row.set_child (box);
            return row;
        }

        private void launch_row (Gtk.ListBoxRow row) {
            var info = row.get_data<AppInfo> ("app-info");
            if (info == null) {
                return;
            }

            menu.popdown ();

            try {
                info.launch (null, null);
            } catch (GLib.Error e) {
                Core.Log.error ("cannot launch %s: %s",
                                info.get_display_name (), e.message);
            }
        }
    }
}
