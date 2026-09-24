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
     */
    public class Chip : Gtk.Label {

        private ChipKind current = ChipKind.NEUTRAL;

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
            Object (label: text);
            add_css_class ("centaur-chip");
            this.kind = kind;
        }
    }
}
