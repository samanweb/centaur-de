namespace Centaur.Topbar {

    /**
     * The title of the focused window.
     *
     * Ellipsised at the end and capped in width: a title is often a path or
     * a command line, and it must never be allowed to push the rest of the bar
     * around as the user switches windows. The app id is only in the tooltip;
     * in the bar it is noise the window itself already shows.
     */
    public class FocusedWindowIndicator : TextIndicator, Indicator {

        private const int MAX_WIDTH_CHARS = 60;

        private Context context;
        private ulong handler = 0;

        public string indicator_id { owned get { return "focused-window"; } }

        public FocusedWindowIndicator (Context context) {
            this.context = context;

            add_css_class ("centaur-indicator");
            add_css_class ("centaur-focused-window");

            caption.ellipsize = Pango.EllipsizeMode.END;
            caption.max_width_chars = MAX_WIDTH_CHARS;
            caption.single_line_mode = true;

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
                // Emptied, not hidden: hiding would unmap the widget, and map
                // is what subscribes, so it would never come back.
                add_css_class ("empty");
                return;
            }

            remove_css_class ("empty");

            label = toplevel.title;
            tooltip_text = toplevel.app_id != ""
                ? @"$(toplevel.title)\n$(toplevel.app_id)"
                : toplevel.title;
        }
    }
}
