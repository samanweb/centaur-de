namespace Centaur.Topbar {

    /**
     * One bar, on one output.
     *
     * A layer-shell surface on the TOP layer, anchored across the top edge with
     * an exclusive zone so maximised windows stop below it rather than under it.
     */
    public class Bar : Gtk.ApplicationWindow {

        private Context context;
        private Gdk.Monitor monitor;

        private Gtk.Box start_box;
        private Gtk.Box center_box;
        private Gtk.Box end_box;
        private ulong[] layout_handlers = {};

        public Bar (Gtk.Application application, Context context, Gdk.Monitor monitor) {
            Object (application: application);

            this.context = context;
            this.monitor = monitor;

            add_css_class ("centaur-topbar");

            init_layer_shell ();
            build_layout ();
            populate ();

            // GSettings outlives this window. Without the unmap half, a bar
            // destroyed on monitor unplug would keep its handlers and go on
            // repopulating a window that is gone.
            map.connect (watch_layout_keys);
            unmap.connect (unwatch_layout_keys);
        }

        /**
         * The layout keys are data, so reordering the bar is a settings change
         * rather than a rebuild of this class.
         */
        private void watch_layout_keys () {
            if (layout_handlers.length > 0) {
                return;
            }
            foreach (var key in new string[] {
                    "layout-start", "layout-center", "layout-end" }) {
                layout_handlers += context.config.topbar.changed[key].connect (
                    () => populate ());
            }
            populate ();
        }

        private void unwatch_layout_keys () {
            foreach (var handler in layout_handlers) {
                context.config.topbar.disconnect (handler);
            }
            layout_handlers = {};
        }

        private void init_layer_shell () {
            GtkLayerShell.init_for_window (this);
            GtkLayerShell.set_namespace (this, "centaur-topbar");
            GtkLayerShell.set_layer (this, GtkLayerShell.Layer.TOP);
            GtkLayerShell.set_monitor (this, monitor);

            GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
            GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
            GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);

            // Reserves our height so that maximised windows do not sit beneath
            // the bar. Without this the desktop looks right and behaves wrongly.
            GtkLayerShell.auto_exclusive_zone_enable (this);
        }

        private void build_layout () {
            start_box  = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            center_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2) {
                halign = Gtk.Align.CENTER,
            };
            end_box    = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2) {
                halign = Gtk.Align.END,
            };

            var layout = new Gtk.CenterBox () {
                start_widget = start_box,
                center_widget = center_box,
                end_widget = end_box,
            };

            set_child (layout);
        }

        private void populate () {
            fill (start_box,  context.config.topbar.get_strv ("layout-start"));
            fill (center_box, context.config.topbar.get_strv ("layout-center"));
            fill (end_box,    context.config.topbar.get_strv ("layout-end"));
        }

        private void fill (Gtk.Box box, string[] ids) {
            Gtk.Widget? child;
            while ((child = box.get_first_child ()) != null) {
                box.remove (child);
            }

            foreach (var id in ids) {
                var indicator = Indicators.create (id, context);
                if (indicator != null) {
                    box.append (indicator);
                }
            }
        }
    }
}
