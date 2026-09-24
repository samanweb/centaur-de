namespace Centaur.Ui {

    public enum ChipKind {
        NEUTRAL, SUCCESS, WARNING, DANGER, INFO, ACCENT;

        public string css_class () {
            switch (this) {
                case SUCCESS: return "success";
                case WARNING: return "warning";
                case DANGER:  return "danger";
                case INFO:    return "info";
                case ACCENT:  return "accent";
                default:      return "";
            }
        }
    }

    /**
     * A small status pill.
     *
     * A chip always carries a word. Colour reinforces the message; it never is
     * the message, because a colour-only signal is invisible to a colourblind
     * user and to a monochrome screenshot.
     *
     * GtkLabel is final in GTK4, so the pill is a box wrapping a label rather
     * than a label subclass. Font and colour inherit down to the caption.
     */
    public class Chip : Gtk.Box {

        private Gtk.Label caption;
        private ChipKind current = ChipKind.NEUTRAL;

        public string text {
            get { return caption.label; }
            set { caption.label = value; }
        }

        public ChipKind kind {
            get { return current; }
            set {
                var previous = current.css_class ();
                if (previous != "") {
                    remove_css_class (previous);
                }
                current = value;
                var next = current.css_class ();
                if (next != "") {
                    add_css_class (next);
                }
            }
        }

        public Chip (string text, ChipKind kind = ChipKind.NEUTRAL) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

            caption = new Gtk.Label (text);
            append (caption);

            halign = Gtk.Align.CENTER;
            valign = Gtk.Align.CENTER;

            add_css_class ("centaur-chip");
            this.kind = kind;
        }
    }
}
