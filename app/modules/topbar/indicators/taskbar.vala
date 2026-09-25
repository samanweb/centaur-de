namespace Centaur.Topbar {

    /**
     * One icon per running application, for as long as it has a window open.
     *
     * Windows are grouped by app id, so three terminals are one button, and
     * buttons keep the order the applications were opened in: a taskbar that
     * reshuffles on every focus change cannot be used without looking.
     *
     * Click brings the application forward. Clicking the one already in front
     * cycles through its windows, or minimises it if it has only one.
     */
    public class TaskbarIndicator : Gtk.Box, Indicator {

        private const int ICON_SIZE = 18;

        private Context context;
        private ulong handler = 0;

        /** What an app id resolved to, misses included. */
        private class App {
            public DesktopAppInfo? info;
            public Icon icon;
        }

        // app id -> App. Resolving can mean reading every .desktop file, so it
        // is done once per application per session, not on every focus change.
        private static HashTable<string, App>? apps = null;

        public string indicator_id { owned get { return "taskbar"; } }

        public TaskbarIndicator (Context context) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

            this.context = context;
            add_css_class ("centaur-taskbar");

            // As in WorkspacesIndicator: the model outlives this widget.
            map.connect (subscribe);
            unmap.connect (unsubscribe);

            rebuild ();
        }

        private void subscribe () {
            if (handler == 0) {
                handler = context.toplevels.changed.connect (rebuild);
            }
            rebuild ();
        }

        private void unsubscribe () {
            if (handler != 0) {
                context.toplevels.disconnect (handler);
                handler = 0;
            }
        }

        private void rebuild () {
            Gtk.Widget? child;
            while ((child = get_first_child ()) != null) {
                remove (child);
            }

            // Grouped in opening order: the first window of an app places it.
            var order = new GenericArray<string> ();
            var groups = new HashTable<string, GenericArray<Window>> (str_hash, str_equal);

            foreach (var window in context.toplevels.list ()) {
                var key = window.group_key;
                var group = groups.lookup (key);
                if (group == null) {
                    group = new GenericArray<Window> ();
                    groups.insert (key, group);
                    order.add (key);
                }
                group.add (window);
            }

            foreach (var key in order.data) {
                append (build_button (groups.lookup (key)));
            }

            // Emptied rather than hidden. A hidden widget is never mapped, and
            // it is map that subscribes to the window list, so a taskbar hidden
            // at startup -- before any window is reported -- would stay hidden
            // for the whole session.
            if (order.length > 0) {
                remove_css_class ("empty");
            } else {
                add_css_class ("empty");
            }
        }

        private Gtk.Widget build_button (GenericArray<Window> group) {
            var app = resolve (group[0].app_id);

            var button = new Gtk.Button () {
                child = new Gtk.Image.from_gicon (app.icon) {
                    pixel_size = ICON_SIZE,
                },
                tooltip_text = describe (group, app.info),
            };
            button.add_css_class ("flat");
            button.add_css_class ("centaur-task");

            var active = false;
            var all_minimized = true;
            foreach (var window in group.data) {
                active |= window.activated;
                all_minimized &= window.minimized;
            }
            if (active) {
                button.add_css_class ("active");
            } else if (all_minimized) {
                button.add_css_class ("minimized");
            }

            button.clicked.connect (() => on_click (group));
            return button;
        }

        private void on_click (GenericArray<Window> group) {
            var toplevels = context.toplevels;

            for (var i = 0; i < group.length; i++) {
                if (!group[i].activated) {
                    continue;
                }
                if (group.length == 1) {
                    toplevels.minimize (group[i]);
                } else {
                    toplevels.activate (group[(i + 1) % group.length]);
                }
                return;
            }

            // Not in front: bring back the window the user last had.
            var latest = group[0];
            foreach (var window in group.data) {
                if (window.focused > latest.focused) {
                    latest = window;
                }
            }
            toplevels.activate (latest);
        }

        private static string describe (GenericArray<Window> group, DesktopAppInfo? info) {
            var name = info != null ? info.get_display_name () : group[0].app_id;
            if (group.length == 1) {
                var title = group[0].title;
                if (name == "" || name == title) {
                    return title;
                }
                return title != "" ? @"$name — $title" : name;
            }
            return @"$name — $(group.length) windows";
        }

        private static App resolve (string app_id) {
            if (apps == null) {
                apps = new HashTable<string, App> (str_hash, str_equal);
            }
            var app = apps.lookup (app_id);
            if (app != null) {
                return app;
            }

            app = new App ();
            app.info = find_app_info (app_id);

            Icon? icon = app.info != null ? app.info.get_icon () : null;

            if (icon == null && app_id != "") {
                var display = Gdk.Display.get_default ();
                var theme = display != null ? Gtk.IconTheme.get_for_display (display) : null;
                foreach (var name in new string[] { app_id, app_id.down () }) {
                    if (theme != null && theme.has_icon (name)) {
                        icon = new ThemedIcon (name);
                        break;
                    }
                }
            }

            app.icon = icon ?? new ThemedIcon ("application-x-executable");
            apps.insert (app_id, app);
            return app;
        }

        /**
         * The .desktop entry behind an app id.
         *
         * Native Wayland apps usually name their desktop file in the app id,
         * but not always in the same case, and X11 apps under Xwayland report
         * their WM class instead -- which the desktop file declares as
         * StartupWMClass. Those are tried in that order, cheapest first.
         */
        private static DesktopAppInfo? find_app_info (string app_id) {
            if (app_id == "") {
                return null;
            }

            foreach (var candidate in new string[] { app_id, app_id.down () }) {
                var info = new DesktopAppInfo (@"$candidate.desktop");
                if (info != null) {
                    return info;
                }
            }

            var wanted = app_id.down ();
            foreach (var app in AppInfo.get_all ()) {
                var info = app as DesktopAppInfo;
                if (info == null) {
                    continue;
                }
                var wm_class = info.get_startup_wm_class ();
                if (wm_class != null && wm_class.down () == wanted) {
                    return info;
                }
                // org.gnome.Nautilus.desktop for an app id of "nautilus".
                var id = info.get_id ();
                if (id != null && id.down ().has_suffix (@".$wanted.desktop")) {
                    return info;
                }
            }
            return null;
        }
    }
}
