namespace Centaur.BaseCenter {

    /**
     * One settings page.
     *
     * A page declares what it is about; the window builds the sidebar and the
     * search index from that declaration. Nothing in the window hard-codes a
     * list of pages or a table of search terms, so adding a page is one file
     * and one line in Pages.all().
     *
     * create_widget() is called on first navigation, never at start-up: a
     * settings window that builds every page to show one is paying for seven
     * pages nobody asked for.
     */
    public interface Page : Object {
        public abstract string id { owned get; }
        public abstract string title { owned get; }
        public abstract string icon { owned get; }
        public abstract string category { owned get; }
        public abstract string[] keywords { owned get; }

        public abstract Gtk.Widget create_widget ();
    }

    public const string CATEGORY_SYSTEM = "System Configuration";
    public const string CATEGORY_HARDWARE = "Hardware & Connectivity";

    namespace Pages {

        /**
         * Every page this build ships, in sidebar order.
         *
         * Pages from the reference screenshots that are not here yet -- Displays
         * & Hardware, Network & Wi-Fi, Bluetooth, Sound & Audio, Power & Battery
         * -- are absent rather than present and empty. A settings window that
         * lists a page and then shows nothing is worse than one that is honestly
         * smaller; see README.md for what each of them needs first.
         */
        public Page[] all () {
            return {
                new OverviewPage (),
                new AppearancePage (),
                new SecurityPage (),
            };
        }
    }

    /** Shared helpers for laying a page out consistently. */
    namespace Layout {

        public Gtk.Box page_box () {
            return new Gtk.Box (Gtk.Orientation.VERTICAL, 16) {
                margin_top = 24,
                margin_bottom = 24,
                margin_start = 24,
                margin_end = 24,
            };
        }

        /**
         * NOT IMPLEMENTED: capping content width on an ultrawide display.
         *
         * set_size_request() is a minimum, not a maximum, so using it here made
         * the window unable to shrink and clipped cards at the default size.
         * A real cap needs a custom Gtk.LayoutManager, since this build uses no
         * libadwaita and so has no AdwClamp. Cards stretching on a very wide
         * monitor is the lesser problem, and is left alone until that exists.
         */
        public Gtk.Widget scroller (Gtk.Widget child) {
            child.hexpand = true;

            return new Gtk.ScrolledWindow () {
                child = child,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vexpand = true,
            };
        }

        public Gtk.Label heading (string text) {
            var label = new Gtk.Label (text) { xalign = 0 };
            label.add_css_class ("title-lg");
            return label;
        }
    }
}
