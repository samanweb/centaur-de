namespace Centaur.BaseCenter {

    /**
     * The Base Center shell: sidebar, search, content.
     *
     * Pure GTK4, no libadwaita. The design language here is Centaur's own, and
     * adopting libadwaita would mean shipping a GNOME dependency whose styling
     * this would then have to override anyway.
     */
    public class Window : Gtk.ApplicationWindow {

        private Gtk.ListBox sidebar;
        private Gtk.Stack content;
        private Gtk.SearchEntry search;
        private Page[] pages;
        private GenericSet<string> built = new GenericSet<string> (str_hash, str_equal);

        public Window (Gtk.Application application) {
            Object (application: application,
                    title: "Base Center",
                    default_width: 1100,
                    default_height: 760);

            pages = Pages.all ();

            build ();
            select_first ();
        }

        private void build () {
            search = new Gtk.SearchEntry () {
                placeholder_text = "Search settings",
                hexpand = true,
            };
            search.add_css_class ("centaur-search");
            search.search_changed.connect (() => rebuild_sidebar (search.text));

            var header = new Gtk.HeaderBar () {
                title_widget = search,
            };
            set_titlebar (header);

            sidebar = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.SINGLE,
            };
            sidebar.add_css_class ("centaur-sidebar");
            sidebar.row_selected.connect (on_row_selected);

            var sidebar_scroller = new Gtk.ScrolledWindow () {
                child = sidebar,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                width_request = 220,
            };

            content = new Gtk.Stack () {
                hexpand = true,
                transition_type = Gtk.StackTransitionType.CROSSFADE,
                transition_duration = 180,
            };
            content.add_css_class ("centaur-content");

            var split = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            split.append (sidebar_scroller);
            split.append (content);

            set_child (split);

            rebuild_sidebar ("");
        }

        /**
         * Rebuilds the sidebar, filtered by the search query.
         *
         * Search matches a page's declared keywords as well as its title, so
         * "refresh rate" finds Displays without Displays being named. Row-level
         * jumping -- scrolling to the matched setting and highlighting it -- is
         * not implemented yet; this filters to the page.
         */
        private void rebuild_sidebar (string query) {
            Gtk.Widget? child;
            while ((child = sidebar.get_first_child ()) != null) {
                sidebar.remove (child);
            }

            var needle = query.down ().strip ();
            var last_category = "";

            foreach (var page in pages) {
                if (needle != "" && !matches (page, needle)) {
                    continue;
                }

                if (page.category != last_category) {
                    sidebar.append (category_row (page.category));
                    last_category = page.category;
                }

                sidebar.append (page_row (page));
            }
        }

        private static bool matches (Page page, string needle) {
            if (needle in page.title.down ()) {
                return true;
            }
            foreach (var keyword in page.keywords) {
                if (needle in keyword.down ()) {
                    return true;
                }
            }
            return false;
        }

        private Gtk.Widget category_row (string title) {
            var label = new Gtk.Label (title.up ()) {
                xalign = 0,
                margin_top = 12,
                margin_bottom = 4,
                margin_start = 12,
            };
            label.add_css_class ("section-heading");

            var row = new Gtk.ListBoxRow () {
                child = label,
                selectable = false,
                activatable = false,
            };
            return row;
        }

        private Gtk.Widget page_row (Page page) {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            box.append (new Gtk.Image.from_icon_name (page.icon) { pixel_size = 16 });
            box.append (new Gtk.Label (page.title) { xalign = 0, hexpand = true });

            var row = new Gtk.ListBoxRow () { child = box };
            row.add_css_class ("centaur-sidebar-row");
            row.set_data<string> ("page-id", page.id);
            return row;
        }

        private void on_row_selected (Gtk.ListBoxRow? row) {
            if (row == null) {
                return;
            }

            var id = row.get_data<string> ("page-id");
            if (id == null) {
                return;
            }

            // Built once, then kept: returning to a page should not lose the
            // scroll position or re-run its D-Bus calls.
            if (!built.contains (id)) {
                foreach (var page in pages) {
                    if (page.id == id) {
                        content.add_named (page.create_widget (), id);
                        built.add (id);
                        break;
                    }
                }
            }

            content.set_visible_child_name (id);
        }

        private void select_first () {
            var row = sidebar.get_row_at_index (1);  // index 0 is a category label
            if (row != null) {
                sidebar.select_row (row);
            }
        }
    }
}
