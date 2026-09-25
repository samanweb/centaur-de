namespace Centaur.Screenshot {

    /**
     * "Screenshot saved", shown for a few seconds under the topbar.
     *
     * A layer-shell overlay rather than a window: it must appear where the
     * user expects, at the top right, and must never take keyboard focus from
     * whatever they were doing -- neither of which a normal Wayland window can
     * promise. It is also what a notification would be, until centaur-notifyd
     * exists.
     */
    public class Toast : Gtk.ApplicationWindow {

        private const uint VISIBLE_SECONDS = 6;
        private const int THUMB_WIDTH = 280;

        // Topbar height plus a gap, so the card sits just under the bar.
        private const int MARGIN_TOP = 40;
        private const int MARGIN_SIDE = 12;

        private uint dismiss_source = 0;

        public Toast.saved (Gtk.Application application, string path) {
            Object (application: application);
            init_layer_shell ();

            var card = card_box ();

            // A decoded thumbnail, not the file: a picture's size request is
            // only a minimum, so a full-resolution image would size the card
            // to the screenshot -- and hold a whole screen of pixels to show
            // a small preview.
            var picture = new Gtk.Picture () {
                paintable = thumbnail (path),
                can_shrink = true,
                content_fit = Gtk.ContentFit.COVER,
                width_request = THUMB_WIDTH,
                height_request = THUMB_WIDTH * 9 / 16,
                cursor = new Gdk.Cursor.from_name ("pointer", null),
                tooltip_text = "Open",
            };
            var frame = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                overflow = Gtk.Overflow.HIDDEN,
            };
            frame.add_css_class ("centaur-screenshot-thumb");
            frame.append (picture);
            var open_click = new Gtk.GestureClick ();
            open_click.released.connect (() => open_uri (File.new_for_path (path).get_uri ()));
            frame.add_controller (open_click);
            card.append (frame);

            card.append (heading ("Screenshot saved"));
            card.append (detail ("Copied to the clipboard · Pictures/Screenshots"));

            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { homogeneous = true };
            var open = new Gtk.Button.with_label ("Open");
            open.clicked.connect (() => open_uri (File.new_for_path (path).get_uri ()));
            var folder = new Gtk.Button.with_label ("Show in Folder");
            folder.clicked.connect (() => {
                open_uri (File.new_for_path (Path.get_dirname (path)).get_uri ());
            });
            actions.append (open);
            actions.append (folder);
            card.append (actions);

            set_child (card);
            arm_dismiss ();
        }

        public Toast.failed (Gtk.Application application, string message) {
            Object (application: application);
            init_layer_shell ();

            var card = card_box ();
            card.add_css_class ("danger");
            card.append (heading ("Screenshot failed"));
            card.append (detail (message));
            set_child (card);
            arm_dismiss ();
        }

        private static Gdk.Texture? thumbnail (string path) {
            try {
                var pixbuf = new Gdk.Pixbuf.from_file_at_scale (path, THUMB_WIDTH, THUMB_WIDTH, true);
                return new Gdk.MemoryTexture (
                    pixbuf.width, pixbuf.height,
                    pixbuf.has_alpha ? Gdk.MemoryFormat.R8G8B8A8 : Gdk.MemoryFormat.R8G8B8,
                    pixbuf.read_pixel_bytes (), pixbuf.rowstride);
            } catch (GLib.Error e) {
                Core.Log.warn ("cannot read %s for its preview: %s", path, e.message);
                return null;
            }
        }

        private void init_layer_shell () {
            add_css_class ("centaur-screenshot-toast");

            GtkLayerShell.init_for_window (this);
            GtkLayerShell.set_namespace (this, "centaur-screenshot");
            GtkLayerShell.set_layer (this, GtkLayerShell.Layer.OVERLAY);
            GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
            GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
            GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, MARGIN_TOP);
            GtkLayerShell.set_margin (this, GtkLayerShell.Edge.RIGHT, MARGIN_SIDE);
            // Clicks only: the keyboard stays with the window the user was in.
            GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.NONE);
        }

        private Gtk.Box card_box () {
            var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                width_request = THUMB_WIDTH,
            };
            card.add_css_class ("centaur-screenshot-card");

            var close = new Gtk.Button.from_icon_name ("window-close-symbolic") {
                halign = Gtk.Align.END,
                tooltip_text = "Dismiss",
            };
            close.add_css_class ("flat");
            close.add_css_class ("centaur-screenshot-close");
            close.clicked.connect (() => close_now ());
            card.append (close);
            return card;
        }

        private static Gtk.Label heading (string text) {
            var label = new Gtk.Label (text) { xalign = 0 };
            label.add_css_class ("centaur-screenshot-heading");
            return label;
        }

        private static Gtk.Label detail (string text) {
            var label = new Gtk.Label (text) {
                xalign = 0,
                wrap = true,
                max_width_chars = 40,
            };
            label.add_css_class ("caption");
            return label;
        }

        /**
         * Closes itself after a few seconds, but never while the pointer is on
         * it: a card that vanishes as you reach for its button is worse than
         * none.
         */
        private void arm_dismiss () {
            var hover = new Gtk.EventControllerMotion ();
            hover.enter.connect (() => {
                if (dismiss_source != 0) {
                    Source.remove (dismiss_source);
                    dismiss_source = 0;
                }
            });
            hover.leave.connect (() => schedule_dismiss ());
            ((Gtk.Widget) this).add_controller (hover);
            schedule_dismiss ();
        }

        private void schedule_dismiss () {
            if (dismiss_source != 0) {
                Source.remove (dismiss_source);
            }
            dismiss_source = Timeout.add_seconds (VISIBLE_SECONDS, () => {
                dismiss_source = 0;
                close_now ();
                return Source.REMOVE;
            });
        }

        private void close_now () {
            if (dismiss_source != 0) {
                Source.remove (dismiss_source);
                dismiss_source = 0;
            }
            destroy ();
        }

        private void open_uri (string uri) {
            try {
                AppInfo.launch_default_for_uri (uri, null);
            } catch (GLib.Error e) {
                Core.Log.warn ("cannot open %s: %s", uri, e.message);
            }
            close_now ();
        }
    }
}
