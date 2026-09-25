namespace Centaur.Screenshot {

    /**
     * The capture window: what to capture, and after how long.
     *
     * It hides itself before capturing -- a screenshot of the screenshot
     * window is the one thing nobody wants -- and waits a moment for the
     * compositor to repaint without it.
     */
    public class Window : Gtk.ApplicationWindow {

        private const uint REPAINT_MS = 350;
        private const int[] DELAYS = { 0, 3, 5, 10 };

        private Mode mode = Mode.AREA;
        private Gtk.DropDown delay;

        /** Emitted once the window is hidden and any delay has passed. */
        public signal void capture_requested (Mode mode);

        public Window (Gtk.Application application) {
            Object (application: application,
                    title: "Screenshot",
                    resizable: false);
            add_css_class ("centaur-window");
            set_titlebar (new Gtk.HeaderBar ());

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 16) {
                margin_top = 20,
                margin_bottom = 20,
                margin_start = 20,
                margin_end = 20,
            };

            // Three modes as a row of large toggles, like every other desktop.
            var modes = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { homogeneous = true };
            Gtk.ToggleButton? group = null;
            var several = monitor_count () > 1;
            foreach (var entry in new string[] { "area", "display", "screen" }) {
                if (entry == "display" && !several) {
                    continue;   // one display: "display" and "screen" are the same
                }
                var button = mode_button (entry);
                if (group == null) {
                    group = button;
                } else {
                    button.group = group;
                }
                modes.append (button);
            }
            group.active = true;
            content.append (modes);

            var options = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            options.add_css_class ("centaur-row");
            var label = new Gtk.Label ("Delay") { xalign = 0, hexpand = true };
            label.add_css_class ("centaur-row-title");
            string[] delay_labels = {};
            foreach (var seconds in DELAYS) {
                delay_labels += seconds == 0 ? "None" : @"$seconds seconds";
            }
            delay = new Gtk.DropDown.from_strings (delay_labels) { valign = Gtk.Align.CENTER };
            options.append (label);
            options.append (delay);
            content.append (options);

            var take = new Gtk.Button.with_label ("Take Screenshot");
            take.add_css_class ("accent");
            take.clicked.connect (() => request ());
            content.append (take);

            set_child (content);
            set_default_widget (take);
        }

        private Gtk.ToggleButton mode_button (string entry) {
            string icon, text;
            switch (entry) {
                case "area":
                    icon = "selection-mode-symbolic"; text = "Area"; break;
                case "display":
                    icon = "video-display-symbolic"; text = "Display"; break;
                default:
                    icon = "view-fullscreen-symbolic"; text = "Screen"; break;
            }
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            box.append (new Gtk.Image.from_icon_name (icon) { pixel_size = 24 });
            box.append (new Gtk.Label (text));

            var button = new Gtk.ToggleButton () { child = box };
            button.add_css_class ("centaur-screenshot-mode");
            var chosen = Mode.parse (entry);
            button.toggled.connect (() => {
                if (button.active) {
                    mode = chosen;
                }
            });
            return button;
        }

        private void request () {
            var seconds = DELAYS[(int) delay.selected];
            hide ();
            // Out of the way before the capture, whatever the delay.
            Timeout.add ((uint) seconds * 1000 + REPAINT_MS, () => {
                capture_requested (mode);
                return Source.REMOVE;
            });
        }

        private static int monitor_count () {
            var display = Gdk.Display.get_default ();
            return display != null ? (int) display.get_monitors ().get_n_items () : 1;
        }
    }
}
