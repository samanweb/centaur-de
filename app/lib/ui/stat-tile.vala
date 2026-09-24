namespace Centaur.Ui {

    /**
     * A single number with a caption, as used across the Overview page.
     *
     * The value is monospaced: tiles are read as a column, and proportional
     * digits will not align.
     */
    public class StatTile : Gtk.Box {

        private Gtk.Label value_label;
        private Gtk.Label caption_label;

        public string value {
            get { return value_label.label; }
            set { value_label.label = value; }
        }

        public string caption {
            get { return caption_label.label; }
            set { caption_label.label = value; }
        }

        public StatTile (string caption, string value = "—") {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 2);

            add_css_class ("centaur-stat-tile");

            value_label = new Gtk.Label (value) { xalign = 0 };
            value_label.add_css_class ("centaur-stat-value");
            value_label.add_css_class ("mono");
            append (value_label);

            caption_label = new Gtk.Label (caption) { xalign = 0 };
            caption_label.add_css_class ("centaur-stat-label");
            append (caption_label);
        }
    }
}
