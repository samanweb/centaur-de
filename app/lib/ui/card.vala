namespace Centaur.Ui {

    /**
     * The grouping surface every Base Center page is built from.
     *
     * A card owns its header and a vertical content area. Callers append rows
     * to it; they never touch its internals.
     */
    public class Card : Gtk.Box {

        private Gtk.Label header_label;
        private Gtk.Box content;

        public string title {
            get { return header_label.label; }
            set {
                header_label.label = value;
                header_label.visible = (value != null && value != "");
            }
        }

        public Card (string? title = null) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);

            add_css_class ("centaur-card");

            header_label = new Gtk.Label (null) {
                xalign = 0,
                visible = false,
            };
            header_label.add_css_class ("centaur-card-header");
            append (header_label);

            content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            append (content);

            if (title != null) {
                this.title = title;
            }
        }

        /** Adds a row. Row separators come from CSS, not from separators. */
        public void add (Gtk.Widget child) {
            content.append (child);
        }

        /** Empties the content area, leaving the header. */
        public void clear () {
            Gtk.Widget? child;
            while ((child = content.get_first_child ()) != null) {
                content.remove (child);
            }
        }

        /** Marks this as the card the page is about. At most one per page. */
        public void set_emphasis (bool emphasised) {
            if (emphasised) {
                add_css_class ("accent");
            } else {
                remove_css_class ("accent");
            }
        }
    }
}
