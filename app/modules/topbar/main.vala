namespace Centaur.Topbar {

    /**
     * centaur-topbar.
     *
     * Resident for the whole session, so its cost is the cost of the desktop
     * being on. Every indicator subscribes rather than polls, and no popover
     * is built until it is first opened.
     */
    public class Application : Gtk.Application {

        private Context? context = null;
        private HashTable<Gdk.Monitor, Bar> bars =
            new HashTable<Gdk.Monitor, Bar> (direct_hash, direct_equal);

        public Application () {
            Object (application_id: "org.centaur.Topbar",
                    flags: ApplicationFlags.DEFAULT_FLAGS);
        }

        public override void startup () {
            base.startup ();

            Ui.Theme.init ();

            var backend = Compositor.Detect.create ();
            context = new Context (backend);

            backend.start.begin ((source, result) => {
                try {
                    backend.start.end (result);
                } catch (GLib.Error e) {
                    Core.Log.warn ("compositor backend did not start: %s", e.message);
                }
                build_bars ();
            });

            // Hold the application open: the bar has no window at the moment
            // the backend is still connecting, and GTK would otherwise quit.
            hold ();
        }

        public override void activate () {
            // Nothing to do. The bars are created once the backend is ready.
        }

        private void build_bars () {
            var display = Gdk.Display.get_default ();
            if (display == null) {
                Core.Log.error ("no Wayland display; cannot start the topbar");
                quit ();
                return;
            }

            var monitors = display.get_monitors ();
            monitors.items_changed.connect (() => refresh_monitors (monitors));
            refresh_monitors (monitors);
        }

        /**
         * Keeps one bar per monitor as displays come and go.
         *
         * Hotplug is not an edge case on a laptop; it happens every time a dock
         * is touched, and a bar left behind on a vanished output is a crash.
         */
        private void refresh_monitors (ListModel monitors) {
            var all_outputs = context.config.topbar.get_boolean ("all-outputs");

            Gdk.Monitor[] live = {};
            for (uint i = 0; i < monitors.get_n_items (); i++) {
                if (!all_outputs && i > 0) {
                    break;
                }
                live += (Gdk.Monitor) monitors.get_item (i);
            }

            var stale = new List<Gdk.Monitor> ();
            bars.foreach ((monitor, bar) => {
                if (!contains_monitor (live, monitor)) {
                    stale.append (monitor);
                }
            });
            foreach (var monitor in stale) {
                var bar = bars.lookup (monitor);
                if (bar != null) {
                    bar.destroy ();
                }
                bars.remove (monitor);
            }

            foreach (var monitor in live) {
                if (bars.contains (monitor)) {
                    continue;
                }
                var bar = new Bar (this, context, monitor);
                bars.insert (monitor, bar);
                bar.present ();
            }
        }

        private static bool contains_monitor (Gdk.Monitor[] list, Gdk.Monitor needle) {
            foreach (var monitor in list) {
                if (monitor == needle) {
                    return true;
                }
            }
            return false;
        }
    }

    public static int main (string[] args) {
        Environment.set_prgname ("centaur-topbar");
        return new Application ().run (args);
    }
}
