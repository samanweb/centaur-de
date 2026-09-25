namespace Centaur.Topbar {

    /** One open window, as the taskbar sees it. */
    public class Window : Object {
        public uint id { get; construct; }
        public string app_id { get; set; default = ""; }
        public string title { get; set; default = ""; }
        public bool activated { get; set; }
        public bool minimized { get; set; }

        /** Opening order, so buttons keep their place as focus moves. */
        public uint64 opened { get; construct; }

        /** Raised each time the window gains focus; highest is most recent. */
        public uint64 focused { get; set; }

        public Window (uint id, uint64 opened) {
            Object (id: id, opened: opened);
        }

        /** Windows without an app id are grouped by title instead. */
        public string group_key {
            owned get { return app_id != "" ? app_id : @"title:$title"; }
        }
    }

    /**
     * The open windows, for every bar in the process.
     *
     * One tracker, however many monitors: the window list is the same on each,
     * and a second protocol client per bar would only multiply the traffic.
     */
    public class Toplevels : Object {

        private Native.ToplevelTracker? tracker = null;
        private HashTable<uint, Window> windows =
            new HashTable<uint, Window> (direct_hash, direct_equal);
        private uint64 clock = 0;
        private uint changed_source = 0;

        /** False off Wayland, where there is no window list to be had. */
        public bool available { get { return tracker != null; } }

        /**
         * Coalesced: opening an application reports its title, app id and
         * state as separate commits, and the taskbar should rebuild once.
         */
        public signal void changed ();

        public Toplevels () {
            var display = Gdk.Display.get_default ();
            if (display != null) {
                tracker = Native.ToplevelTracker.create (display, on_event);
            }
            if (tracker == null) {
                Core.Log.debug ("not on Wayland; taskbar unavailable");
            }
        }

        /** All open windows, in the order they were opened. */
        public List<Window> list () {
            var result = new List<Window> ();
            foreach (var window in windows.get_values ()) {
                result.insert_sorted (window, (a, b) => {
                    return a.opened < b.opened ? -1 : (a.opened > b.opened ? 1 : 0);
                });
            }
            return result;
        }

        public void activate (Window window) {
            if (tracker != null) {
                tracker.activate (window.id);
            }
        }

        public void minimize (Window window) {
            if (tracker != null) {
                tracker.minimize (window.id);
            }
        }

        private void on_event (Native.ToplevelEvent event, uint id, string app_id,
                               string title, bool activated, bool minimized) {
            if (event == Native.ToplevelEvent.CLOSED) {
                windows.remove (id);
                queue_changed ();
                return;
            }

            var window = windows.lookup (id);
            if (window == null) {
                window = new Window (id, ++clock);
                windows.insert (id, window);
            }

            if (activated && !window.activated) {
                window.focused = ++clock;
            }
            window.app_id = app_id;
            window.title = title;
            window.activated = activated;
            window.minimized = minimized;

            queue_changed ();
        }

        private void queue_changed () {
            if (changed_source != 0) {
                return;
            }
            changed_source = Idle.add (() => {
                changed_source = 0;
                changed ();
                return Source.REMOVE;
            });
        }
    }
}
