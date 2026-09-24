namespace Centaur.Topbar {

    /**
     * The title of the focused window.
     *
     * Monospaced and ellipsised at the end: a title is often a path or a
     * command line, and it must never be allowed to push the rest of the bar
     * around as the user switches windows.
     */
    public class FocusedWindowIndicator : Gtk.Label, Indicator {

        private const int MAX_WIDTH_CHARS = 60;

        private Context context;
        private ulong handler = 0;

        public string indicator_id { owned get { return "focused-window"; } }

        public FocusedWindowIndicator (Context context) {
            this.context = context;

            add_css_class ("centaur-indicator");
            add_css_class ("centaur-focused-window");

            ellipsize = Pango.EllipsizeMode.END;
            max_width_chars = MAX_WIDTH_CHARS;
            single_line_mode = true;

            // As in WorkspacesIndicator: the backend outlives this widget.
            map.connect (subscribe);
            unmap.connect (unsubscribe);

            update ();
        }

        private void subscribe () {
            if (handler == 0) {
                handler = context.compositor.focus_changed.connect (update);
            }
            update ();
        }

        private void unsubscribe () {
            if (handler != 0) {
                ((Object) context.compositor).disconnect (handler);
                handler = 0;
            }
        }

        private void update () {
            var toplevel = context.compositor.focused_toplevel ();

            if (toplevel == null || toplevel.title == "") {
                label = "";
                tooltip_text = null;
                visible = false;
                return;
            }

            visible = true;

            if (toplevel.app_id != "") {
                label = @"$(toplevel.app_id): $(toplevel.title)";
            } else {
                label = toplevel.title;
            }

            tooltip_text = label;
        }
    }
}
