namespace Centaur.BackgroundSettings {

    /**
     * Choose the desktop wallpaper.
     *
     * Every change is written to org.centaur.appearance straight away and
     * centaur-bg repaints from it, so there is no Apply button: a wallpaper
     * cannot leave the desktop unusable the way a bad resolution can.
     */
    public class Window : Gtk.ApplicationWindow {

        private const int THUMB_WIDTH = 224;
        private const int THUMB_HEIGHT = 126;
        private const int PREVIEW_WIDTH = 640;
        private const int MAX_DEPTH = 3;   // KDE packages nest images in contents/images/

        private const string[] MODES = { "fill", "fit", "stretch", "center", "tile", "solid" };
        private const string[] MODE_LABELS = {
            "Fill screen", "Fit to screen", "Stretch", "Center", "Tile", "Solid colour only",
        };

        private Settings settings;

        private Gtk.Picture preview;
        private Gtk.Box preview_frame;
        private Gtk.DrawingArea backdrop;
        private Gdk.RGBA backdrop_color = Gdk.RGBA () { red = 0, green = 0, blue = 0, alpha = 1 };
        private Gtk.FlowBox grid;
        private Gtk.DropDown mode;
        private Gtk.ColorDialogButton color;
        private Gtk.Button remove_button;
        private Gtk.Label empty_label;

        // path -> its tile, for selection and removal.
        private HashTable<string, Gtk.FlowBoxChild> tiles =
            new HashTable<string, Gtk.FlowBoxChild> (str_hash, str_equal);
        private bool updating = false;

        // Thumbnails decode one at a time: a folder of 4K photos decoded in
        // parallel is a memory spike for no visible gain.
        private Queue<string> thumb_queue = new Queue<string> ();
        private bool thumbs_running = false;

        public Window (Gtk.Application application) {
            Object (application: application,
                    title: "Background",
                    default_width: 760,
                    default_height: 780);

            add_css_class ("centaur-window");
            settings = Core.Config.get_default ().appearance;

            build ();
            sync_from_settings ();
            scan_all.begin ();

            foreach (var key in new string[] { "wallpaper", "wallpaper-mode", "background-color" }) {
                settings.changed[key].connect (() => sync_from_settings ());
            }
        }

        // --- building -----------------------------------------------------

        private void build () {
            set_titlebar (new Gtk.HeaderBar ());

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 16) {
                margin_top = 24,
                margin_bottom = 24,
                margin_start = 24,
                margin_end = 24,
            };

            // Preview, shaped like the first monitor.
            preview = new Gtk.Picture () {
                can_shrink = true,
                content_fit = Gtk.ContentFit.COVER,
                hexpand = true,
                vexpand = true,
            };
            // The background colour is painted under the picture, where it
            // shows through exactly as it will around a 'fit' or 'center'
            // wallpaper.
            backdrop = new Gtk.DrawingArea () { hexpand = true, vexpand = true };
            backdrop.set_draw_func ((area, cr, width, height) => {
                Gdk.cairo_set_source_rgba (cr, backdrop_color);
                cr.paint ();
            });
            var layers = new Gtk.Overlay () { child = backdrop };
            layers.add_overlay (preview);

            preview_frame = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                overflow = Gtk.Overflow.HIDDEN,
            };
            preview_frame.add_css_class ("centaur-wallpaper-preview");
            preview_frame.append (layers);

            var aspect = new Gtk.AspectFrame (0.5f, 0.5f, monitor_ratio (), false) {
                child = preview_frame,
                height_request = 280,
            };
            content.append (aspect);

            // How it covers the screen, and the colour behind it.
            var options = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            options.add_css_class ("centaur-card");

            mode = new Gtk.DropDown.from_strings (MODE_LABELS);
            mode.notify["selected"].connect (() => {
                if (!updating && mode.selected < MODES.length) {
                    settings.set_string ("wallpaper-mode", MODES[mode.selected]);
                }
            });
            options.append (row ("Position", mode));

            color = new Gtk.ColorDialogButton (new Gtk.ColorDialog () { with_alpha = false });
            color.notify["rgba"].connect (() => {
                if (!updating) {
                    settings.set_string ("background-color", to_hex (chosen_color ()));
                }
            });
            options.append (row ("Background colour", color));
            content.append (options);

            // The wallpapers.
            var library = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            library.add_css_class ("centaur-card");

            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var heading = new Gtk.Label ("Wallpapers") { xalign = 0, hexpand = true };
            heading.add_css_class ("centaur-card-header");
            header.append (heading);

            remove_button = new Gtk.Button.with_label ("Remove") {
                sensitive = false,
                tooltip_text = "Remove a picture you added",
            };
            remove_button.clicked.connect (() => remove_selected.begin ());
            header.append (remove_button);

            var add = new Gtk.Button.with_label ("Add Picture…");
            add.add_css_class ("accent");
            add.clicked.connect (() => add_picture.begin ());
            header.append (add);
            library.append (header);

            grid = new Gtk.FlowBox () {
                selection_mode = Gtk.SelectionMode.SINGLE,
                homogeneous = true,
                min_children_per_line = 2,
                max_children_per_line = 6,
                column_spacing = 12,
                row_spacing = 12,
                activate_on_single_click = true,
            };
            grid.add_css_class ("centaur-wallpaper-grid");
            grid.child_activated.connect (on_activated);
            grid.selected_children_changed.connect (update_remove_button);
            library.append (grid);

            empty_label = new Gtk.Label ("No wallpapers found. Add a picture to get started.") {
                visible = false,
                margin_top = 12,
                margin_bottom = 12,
            };
            empty_label.add_css_class ("dim");
            library.append (empty_label);

            content.append (library);

            set_child (new Gtk.ScrolledWindow () {
                child = content,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
            });
        }

        private static Gtk.Widget row (string title, Gtk.Widget control) {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            box.add_css_class ("centaur-row");
            var label = new Gtk.Label (title) { xalign = 0, hexpand = true };
            label.add_css_class ("centaur-row-title");
            control.valign = Gtk.Align.CENTER;
            box.append (label);
            box.append (control);
            return box;
        }

        /**
         * Read through the property: the Vala binding of
         * gtk_color_dialog_button_get_rgba() generates a call with the wrong
         * arity for its const struct return.
         */
        private Gdk.RGBA chosen_color () {
            var value = Value (typeof (Gdk.RGBA));
            color.get_property ("rgba", ref value);
            var rgba = (Gdk.RGBA*) value.get_boxed ();
            return rgba != null ? *rgba : Gdk.RGBA () { red = 0, green = 0, blue = 0, alpha = 1 };
        }

        private static float monitor_ratio () {
            var display = Gdk.Display.get_default ();
            if (display != null) {
                var monitors = display.get_monitors ();
                if (monitors.get_n_items () > 0) {
                    var geometry = ((Gdk.Monitor) monitors.get_item (0)).geometry;
                    if (geometry.height > 0) {
                        return (float) geometry.width / geometry.height;
                    }
                }
            }
            return 16f / 9f;
        }

        // --- settings <-> controls ----------------------------------------

        private string current_image () {
            return Core.Wallpaper.resolve (settings.get_string ("wallpaper")) ?? "";
        }

        private void sync_from_settings () {
            updating = true;

            var current_mode = settings.get_string ("wallpaper-mode");
            for (var i = 0; i < MODES.length; i++) {
                if (MODES[i] == current_mode) {
                    mode.selected = i;
                }
            }

            var rgba = Gdk.RGBA ();
            if (!rgba.parse (settings.get_string ("background-color"))) {
                rgba.parse ("#0b0f14");
            }
            color.rgba = rgba;
            apply_preview_background (rgba);

            var image = current_image ();
            var tile = tiles.lookup (image);
            if (tile != null) {
                grid.select_child (tile);
            } else {
                grid.unselect_all ();
            }

            updating = false;
            update_preview.begin ();
        }

        private void apply_preview_background (Gdk.RGBA rgba) {
            backdrop_color = rgba;
            backdrop.queue_draw ();
        }

        private async void update_preview () {
            var current_mode = settings.get_string ("wallpaper-mode");
            if (current_mode == "solid") {
                preview.paintable = null;
                return;
            }

            // The picture's fit mirrors what swaybg will do.
            switch (current_mode) {
                case "fit":     preview.content_fit = Gtk.ContentFit.CONTAIN; break;
                case "stretch": preview.content_fit = Gtk.ContentFit.FILL; break;
                case "center":  preview.content_fit = Gtk.ContentFit.SCALE_DOWN; break;
                default:        preview.content_fit = Gtk.ContentFit.COVER; break;
            }

            var image = current_image ();
            if (image == "") {
                preview.paintable = null;
                return;
            }
            var texture = yield load_texture (image, PREVIEW_WIDTH, PREVIEW_WIDTH);
            // Only if it is still the wallpaper by the time it has decoded.
            if (texture != null && image == current_image ()) {
                preview.paintable = texture;
            }
        }

        private static string to_hex (Gdk.RGBA rgba) {
            return "#%02x%02x%02x".printf ((uint) Math.round (rgba.red * 255),
                                           (uint) Math.round (rgba.green * 255),
                                           (uint) Math.round (rgba.blue * 255));
        }

        // --- the library --------------------------------------------------

        private async void scan_all () {
            foreach (var dir in Core.Wallpaper.search_dirs ()) {
                yield scan (File.new_for_path (dir), 0);
            }
            empty_label.visible = tiles.size () == 0;
            sync_from_settings ();
        }

        private async void scan (File dir, int depth) {
            FileEnumerator enumerator;
            try {
                enumerator = yield dir.enumerate_children_async (
                    "standard::name,standard::type,standard::is-hidden",
                    FileQueryInfoFlags.NONE, Priority.LOW, null);
            } catch (GLib.Error e) {
                return;   // missing or unreadable: nothing to show from it
            }

            var files = new GenericArray<string> ();
            var subdirs = new GenericArray<File> ();
            try {
                List<FileInfo> batch;
                while ((batch = yield enumerator.next_files_async (64, Priority.LOW)) != null) {
                    foreach (var info in batch) {
                        if (info.get_is_hidden ()) {
                            continue;
                        }
                        var child = dir.get_child (info.get_name ());
                        if (info.get_file_type () == FileType.DIRECTORY) {
                            subdirs.add (child);
                        } else if (Core.Wallpaper.is_image (info.get_name ())) {
                            files.add (child.get_path ());
                        }
                    }
                }
            } catch (GLib.Error e) {
                // Keep what was read before the error.
            }

            files.sort (strcmp);
            foreach (var path in files.data) {
                add_tile (path);
            }
            if (depth < MAX_DEPTH) {
                foreach (var subdir in subdirs.data) {
                    yield scan (subdir, depth + 1);
                }
            }
        }

        private Gtk.FlowBoxChild add_tile (string path) {
            var existing = tiles.lookup (path);
            if (existing != null) {
                return existing;   // the same folder reached twice
            }

            var picture = new Gtk.Picture () {
                can_shrink = true,
                content_fit = Gtk.ContentFit.COVER,
                width_request = THUMB_WIDTH,
                height_request = THUMB_HEIGHT,
            };
            var frame = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                overflow = Gtk.Overflow.HIDDEN,
            };
            frame.add_css_class ("centaur-wallpaper");
            frame.append (picture);

            var child = new Gtk.FlowBoxChild () {
                child = frame,
                tooltip_text = Path.get_basename (path),
            };
            child.set_data<string> ("path", path);
            grid.append (child);
            tiles.insert (path, child);
            empty_label.visible = false;

            thumb_queue.push_tail (path);
            run_thumbnails.begin ();
            return child;
        }

        private async void run_thumbnails () {
            if (thumbs_running) {
                return;
            }
            thumbs_running = true;
            string? path;
            while ((path = thumb_queue.pop_head ()) != null) {
                var tile = tiles.lookup (path);
                if (tile == null) {
                    continue;   // removed while queued
                }
                var texture = yield load_texture (path, THUMB_WIDTH * 2, THUMB_HEIGHT * 2);
                var frame = (Gtk.Box) tile.child;
                ((Gtk.Picture) frame.get_first_child ()).paintable = texture;
            }
            thumbs_running = false;
        }

        /**
         * Decodes at a reduced size, so a 6000-pixel photo costs a thumbnail's
         * memory rather than its own. Null for anything that will not decode.
         */
        private static async Gdk.Texture? load_texture (string path, int width, int height) {
            try {
                var stream = yield File.new_for_path (path).read_async (Priority.LOW);
                var pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async (
                    stream, width, height, true, null);
                return new Gdk.MemoryTexture (
                    pixbuf.width, pixbuf.height,
                    pixbuf.has_alpha ? Gdk.MemoryFormat.R8G8B8A8 : Gdk.MemoryFormat.R8G8B8,
                    pixbuf.read_pixel_bytes (), pixbuf.rowstride);
            } catch (GLib.Error e) {
                Core.Log.debug ("cannot load %s: %s", path, e.message);
                return null;
            }
        }

        // --- actions -------------------------------------------------------

        private void on_activated (Gtk.FlowBoxChild child) {
            if (updating) {
                return;
            }
            var path = child.get_data<string> ("path");
            if (path == null) {
                return;
            }
            settings.set_string ("wallpaper", path);
            // Picking a picture while in solid-colour mode means "show it".
            if (settings.get_string ("wallpaper-mode") == "solid") {
                settings.set_string ("wallpaper-mode", "fill");
            }
        }

        private bool is_user_picture (string path) {
            return path.has_prefix (Core.Wallpaper.user_dir () + "/");
        }

        private string? selected_path () {
            var selected = grid.get_selected_children ();
            return selected != null ? selected.data.get_data<string> ("path") : null;
        }

        private void update_remove_button () {
            var path = selected_path ();
            remove_button.sensitive = path != null && is_user_picture (path);
        }

        /**
         * Copies the picture into the user's backgrounds folder, so the
         * wallpaper survives the original being moved, renamed or on a drive
         * that is not always mounted.
         */
        private async void add_picture () {
            var filter = new Gtk.FileFilter () { name = "Images" };
            filter.add_mime_type ("image/*");
            var filters = new ListStore (typeof (Gtk.FileFilter));
            filters.append (filter);

            var dialog = new Gtk.FileDialog () {
                title = "Add Picture",
                filters = filters,
                modal = true,
            };

            File source;
            try {
                source = yield dialog.open (this, null);
            } catch (GLib.Error e) {
                return;   // cancelled
            }

            var dir = File.new_for_path (Core.Wallpaper.user_dir ());
            try {
                dir.make_directory_with_parents ();
            } catch (IOError.EXISTS e) {
                // fine
            } catch (GLib.Error e) {
                report ("Could not create %s: %s".printf (dir.get_path (), e.message));
                return;
            }

            var target = unique_target (dir, source.get_basename ());
            try {
                yield source.copy_async (target, FileCopyFlags.NONE, Priority.DEFAULT, null, null);
            } catch (GLib.Error e) {
                report ("Could not copy the picture: %s".printf (e.message));
                return;
            }

            var tile = add_tile (target.get_path ());
            grid.select_child (tile);
            on_activated (tile);
        }

        private static File unique_target (File dir, string name) {
            var target = dir.get_child (name);
            var dot = name.last_index_of (".");
            var stem = dot > 0 ? name.substring (0, dot) : name;
            var extension = dot > 0 ? name.substring (dot) : "";
            for (var i = 2; target.query_exists (); i++) {
                target = dir.get_child (@"$stem-$i$extension");
            }
            return target;
        }

        private async void remove_selected () {
            var path = selected_path ();
            if (path == null || !is_user_picture (path)) {
                return;
            }
            try {
                yield File.new_for_path (path).delete_async (Priority.DEFAULT, null);
            } catch (GLib.Error e) {
                report ("Could not remove the picture: %s".printf (e.message));
                return;
            }

            var tile = tiles.lookup (path);
            if (tile != null) {
                grid.remove (tile);
                tiles.remove (path);
            }
            // The wallpaper it was is gone; fall back to the default rather
            // than leave the key pointing at nothing.
            if (settings.get_string ("wallpaper") == path) {
                settings.reset ("wallpaper");
            }
            empty_label.visible = tiles.size () == 0;
            update_remove_button ();
        }

        private void report (string message) {
            new Gtk.AlertDialog ("Background not changed") { detail = message }.show (this);
        }
    }
}
