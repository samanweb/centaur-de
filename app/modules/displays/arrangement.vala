namespace Centaur.DisplaySettings {

    /**
     * The monitors drawn to scale, draggable into place.
     *
     * Each enabled display is a tile in a Gtk.Fixed, so colours come from the
     * stylesheet like everything else rather than being painted by hand. A
     * dropped tile snaps edge-to-edge against its nearest neighbour: a gap or
     * an overlap between monitors is never what anyone wants, and the pointer
     * cannot place a tile to the pixel.
     */
    public class Arrangement : Gtk.Box {

        private const int CANVAS_WIDTH = 560;
        private const int CANVAS_HEIGHT = 200;
        private const int PADDING = 16;

        /** Logical pixels within which an edge snaps to line up with another. */
        private const int ALIGN_DISTANCE = 64;

        private Gtk.Fixed fixed;
        private Displays.Head[] heads = {};
        private string selected = "";

        // Layout -> canvas transform for the current build.
        private double ratio = 1.0;
        private double offset_x = 0;
        private double offset_y = 0;

        public signal void head_selected (string name);

        /** A tile was dropped; the head's x and y are already updated. */
        public signal void head_moved (string name);

        public Arrangement () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            add_css_class ("centaur-display-canvas");

            fixed = new Gtk.Fixed () {
                width_request = CANVAS_WIDTH,
                height_request = CANVAS_HEIGHT,
                halign = Gtk.Align.CENTER,
                overflow = Gtk.Overflow.HIDDEN,
            };
            append (fixed);
        }

        public void set_heads (Displays.Head[] heads, string selected) {
            this.heads = heads;
            this.selected = selected;
            rebuild ();
        }

        private void rebuild () {
            Gtk.Widget? child;
            while ((child = fixed.get_first_child ()) != null) {
                fixed.remove (child);
            }

            fit_layout ();

            var enabled = 0;
            foreach (var head in heads) {
                if (head.enabled) {
                    enabled++;
                }
            }

            foreach (var head in heads) {
                if (!head.enabled) {
                    continue;
                }
                var tile = build_tile (head, enabled > 1);
                fixed.put (tile, to_canvas_x (head.x), to_canvas_y (head.y));
            }
        }

        /** Fits the whole layout in the canvas, centred, at one scale. */
        private void fit_layout () {
            int min_x = int.MAX, min_y = int.MAX, max_x = int.MIN, max_y = int.MIN;
            foreach (var head in heads) {
                if (!head.enabled) {
                    continue;
                }
                min_x = int.min (min_x, head.x);
                min_y = int.min (min_y, head.y);
                max_x = int.max (max_x, head.x + head.logical_width);
                max_y = int.max (max_y, head.y + head.logical_height);
            }
            if (min_x == int.MAX) {
                ratio = 1.0;
                return;
            }

            var width = double.max (max_x - min_x, 1);
            var height = double.max (max_y - min_y, 1);
            ratio = double.min ((CANVAS_WIDTH - 2 * PADDING) / width,
                                (CANVAS_HEIGHT - 2 * PADDING) / height);

            offset_x = (CANVAS_WIDTH - width * ratio) / 2 - min_x * ratio;
            offset_y = (CANVAS_HEIGHT - height * ratio) / 2 - min_y * ratio;
        }

        private double to_canvas_x (int x) { return offset_x + x * ratio; }
        private double to_canvas_y (int y) { return offset_y + y * ratio; }

        private Gtk.Widget build_tile (Displays.Head head, bool draggable) {
            var tile = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                width_request = int.max ((int) (head.logical_width * ratio), 24),
                height_request = int.max ((int) (head.logical_height * ratio), 24),
                valign = Gtk.Align.START,
                tooltip_text = head.title,
            };
            tile.add_css_class ("centaur-display-tile");
            if (head.name == selected) {
                tile.add_css_class ("selected");
            }

            var name = new Gtk.Label (head.name) {
                vexpand = true,
                valign = Gtk.Align.END,
                ellipsize = Pango.EllipsizeMode.END,
            };
            name.add_css_class ("centaur-display-tile-name");
            tile.append (name);

            var mode = head.effective_mode ();
            var size = new Gtk.Label (mode != null ? mode.size_label () : "") {
                vexpand = true,
                valign = Gtk.Align.START,
                ellipsize = Pango.EllipsizeMode.END,
            };
            size.add_css_class ("caption");
            tile.append (size);

            // One gesture for both: a drag shorter than a few pixels is a
            // click, so selecting never nudges a monitor by accident. The tile
            // is reached through the gesture, not captured: capturing it would
            // make the tile own a closure that owns the tile.
            var drag = new Gtk.GestureDrag ();
            double start_x = 0, start_y = 0;
            drag.drag_begin.connect ((gesture, x, y) => {
                double tx, ty;
                fixed.get_child_position (gesture.get_widget (), out tx, out ty);
                start_x = tx;
                start_y = ty;
            });
            drag.drag_update.connect ((gesture, dx, dy) => {
                if (draggable) {
                    fixed.move (gesture.get_widget (), start_x + dx, start_y + dy);
                }
            });
            drag.drag_end.connect ((gesture, dx, dy) => {
                if (!draggable || Math.fabs (dx) + Math.fabs (dy) < 4) {
                    selected = head.name;
                    head_selected (head.name);
                    return;
                }
                var x = (int) Math.round ((start_x + dx - offset_x) / ratio);
                var y = (int) Math.round ((start_y + dy - offset_y) / ratio);
                snap (head, x, y);
                selected = head.name;
                head_selected (head.name);
                head_moved (head.name);
            });
            tile.add_controller (drag);

            return tile;
        }

        /**
         * Places `moving` against the neighbour edge nearest to where it was
         * dropped, never overlapping anything, and lines its edges up with
         * that neighbour's when they are close.
         */
        private void snap (Displays.Head moving, int x, int y) {
            var w = moving.logical_width;
            var h = moving.logical_height;

            var best_x = moving.x;
            var best_y = moving.y;
            var best_distance = double.MAX;

            foreach (var other in heads) {
                if (other == moving || !other.enabled) {
                    continue;
                }
                var ox = other.x;
                var oy = other.y;
                var ow = other.logical_width;
                var oh = other.logical_height;

                // Beside it: keep the dropped height, but always touching.
                var side_y = align (y.clamp (oy - h + 1, oy + oh - 1), h, oy, oh);
                // Above or below it: the same for the horizontal position.
                var stack_x = align (x.clamp (ox - w + 1, ox + ow - 1), w, ox, ow);

                int[,] candidates = {
                    { ox + ow, side_y },   // right of
                    { ox - w,  side_y },   // left of
                    { stack_x, oy + oh },  // below
                    { stack_x, oy - h  },  // above
                };

                for (var i = 0; i < 4; i++) {
                    var cx = candidates[i, 0];
                    var cy = candidates[i, 1];
                    if (overlaps_any (moving, cx, cy, w, h)) {
                        continue;
                    }
                    var distance = Math.hypot (cx - x, cy - y);
                    if (distance < best_distance) {
                        best_distance = distance;
                        best_x = cx;
                        best_y = cy;
                    }
                }
            }

            moving.x = best_x;
            moving.y = best_y;
        }

        /** Snaps a start or end edge onto the neighbour's when within reach. */
        private static int align (int position, int length, int other, int other_length) {
            if ((position - other).abs () < ALIGN_DISTANCE) {
                return other;
            }
            var end = other + other_length - length;
            if ((position - end).abs () < ALIGN_DISTANCE) {
                return end;
            }
            return position;
        }

        private bool overlaps_any (Displays.Head moving, int x, int y, int w, int h) {
            foreach (var other in heads) {
                if (other == moving || !other.enabled) {
                    continue;
                }
                if (x < other.x + other.logical_width && x + w > other.x
                    && y < other.y + other.logical_height && y + h > other.y) {
                    return true;
                }
            }
            return false;
        }
    }
}
