namespace Centaur.Topbar {

    /**
     * The workspace pager.
     *
     * Present only when the running compositor can actually report workspaces;
     * on labwc the factory returns null and the bar has no pager at all rather
     * than an empty one.
     *
     * Three states must survive a monochrome screenshot, so the active
     * workspace differs from an occupied one by weight and background, not by
     * colour alone.
     */
    public class WorkspacesIndicator : Gtk.Box, Indicator {

        private Context context;
        private ulong handler = 0;

        public string indicator_id { owned get { return "workspaces"; } }

        public WorkspacesIndicator (Context context) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

            this.context = context;
            add_css_class ("centaur-indicator");

            // The backend outlives this widget, so the subscription has to be
            // released when the bar goes away.
            map.connect (subscribe);
            unmap.connect (unsubscribe);

            rebuild ();
        }

        private void subscribe () {
            if (handler == 0) {
                handler = context.compositor.workspaces_changed.connect (rebuild);
            }
            rebuild ();
        }

        private void unsubscribe () {
            if (handler != 0) {
                ((Object) context.compositor).disconnect (handler);
                handler = 0;
            }
        }

        private void rebuild () {
            Gtk.Widget? child;
            while ((child = get_first_child ()) != null) {
                remove (child);
            }

            foreach (var workspace in context.compositor.list_workspaces ()) {
                append (build_button (workspace));
            }
        }

        private Gtk.Widget build_button (Compositor.Workspace workspace) {
            var button = new Gtk.Button.with_label (workspace.name);
            button.add_css_class ("centaur-workspace");
            button.add_css_class ("flat");

            if (workspace.active) {
                button.add_css_class ("active");
            } else if (workspace.occupied) {
                button.add_css_class ("occupied");
            }

            var id = workspace.id;
            button.clicked.connect (() => switch_to.begin (id));

            return button;
        }

        private async void switch_to (string id) {
            try {
                yield context.compositor.switch_workspace (id);
            } catch (GLib.Error e) {
                Core.Log.warn ("cannot switch to workspace %s: %s", id, e.message);
            }
        }
    }
}
