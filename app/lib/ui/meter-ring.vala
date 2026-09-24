namespace Centaur.Ui {

    /**
     * The circular gauge used for CPU utilisation and battery level.
     *
     * Geometry is fixed here so every ring in the desktop matches: 6px stroke,
     * round cap, sweep starting at twelve o'clock and running clockwise.
     *
     * Colour comes from the CSS 'color' property of this widget, which the
     * design system points at the accent. The unfilled track is that same
     * colour at 18% alpha -- a ring is one drawing area, so a second CSS class
     * could not reach it.
     */
    public class MeterRing : Gtk.Box {

        private const double STROKE = 6.0;
        private const double TRACK_ALPHA = 0.18;
        private const int DEFAULT_SIZE = 96;

        private const double WARNING_AT = 0.80;
        private const double DANGER_AT = 0.95;

        private Gtk.DrawingArea area;
        private Gtk.Label centre_label;
        private Gtk.Overlay overlay;
        private double current = 0.0;

        /** 0.0 to 1.0. Values outside the range are clamped, not rejected. */
        public double fraction {
            get { return current; }
            set {
                current = value.clamp (0.0, 1.0);
                apply_threshold_class ();
                area.queue_draw ();
            }
        }

        public string label_text {
            get { return centre_label.label; }
            set { centre_label.label = value; }
        }

        /**
         * Whether the ring changes colour past the warning and danger marks.
         *
         * Off for gauges where a high reading is normal -- a full battery is
         * not a problem, and colouring it red would be nonsense.
         */
        public bool threshold_colouring { get; set; default = true; }

        public MeterRing (int size = DEFAULT_SIZE) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);

            add_css_class ("centaur-meter-ring");

            area = new Gtk.DrawingArea () {
                content_width = size,
                content_height = size,
                hexpand = false,
                vexpand = false,
            };
            area.set_draw_func (draw);

            centre_label = new Gtk.Label ("") {
                halign = Gtk.Align.CENTER,
                valign = Gtk.Align.CENTER,
            };
            centre_label.add_css_class ("title-lg");
            centre_label.add_css_class ("mono");

            overlay = new Gtk.Overlay ();
            overlay.set_child (area);
            overlay.add_overlay (centre_label);
            append (overlay);
        }

        private void apply_threshold_class () {
            remove_css_class ("warning");
            remove_css_class ("danger");

            if (!threshold_colouring) {
                return;
            }
            if (current >= DANGER_AT) {
                add_css_class ("danger");
            } else if (current >= WARNING_AT) {
                add_css_class ("warning");
            }
        }

        private void draw (Gtk.DrawingArea da, Cairo.Context cr, int width, int height) {
            // Read the resolved CSS colour rather than a literal, so a change of
            // accent repaints correctly without this widget knowing the palette.
            var colour = this.get_color ();

            var extent = double.min ((double) width, (double) height);
            var radius = (extent - STROKE) / 2.0;
            if (radius <= 0) {
                return;
            }

            var cx = width / 2.0;
            var cy = height / 2.0;

            cr.set_line_width (STROKE);
            cr.set_line_cap (Cairo.LineCap.ROUND);

            cr.set_source_rgba (colour.red, colour.green, colour.blue,
                                colour.alpha * TRACK_ALPHA);
            cr.arc (cx, cy, radius, 0, 2 * Math.PI);
            cr.stroke ();

            if (current <= 0.0) {
                return;
            }

            cr.set_source_rgba (colour.red, colour.green, colour.blue, colour.alpha);
            var start = -Math.PI / 2.0;
            cr.arc (cx, cy, radius, start, start + 2 * Math.PI * current);
            cr.stroke ();
        }
    }
}
