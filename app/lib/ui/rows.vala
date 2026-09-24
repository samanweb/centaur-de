namespace Centaur.Ui {

    /**
     * A labelled line inside a Card: title, optional subtitle, trailing control.
     *
     * Separators between rows come from CSS ('.centaur-row + .centaur-row'), so
     * the first row needs no special case and callers never add separators.
     */
    public class Row : Gtk.Box {

        private Gtk.Label title_label;
        private Gtk.Label subtitle_label;
        private Gtk.Box text_box;
        private Gtk.Widget? suffix = null;

        public string title {
            get { return title_label.label; }
            set { title_label.label = value; }
        }

        public string subtitle {
            get { return subtitle_label.label; }
            set {
                subtitle_label.label = value;
                subtitle_label.visible = (value != null && value != "");
            }
        }

        public Row (string title, string? subtitle = null) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);

            add_css_class ("centaur-row");

            text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                hexpand = true,
                valign = Gtk.Align.CENTER,
            };

            title_label = new Gtk.Label (title) { xalign = 0, wrap = true };
            title_label.add_css_class ("centaur-row-title");
            text_box.append (title_label);

            subtitle_label = new Gtk.Label (null) {
                xalign = 0,
                wrap = true,
                visible = false,
            };
            subtitle_label.add_css_class ("centaur-row-subtitle");
            text_box.append (subtitle_label);

            append (text_box);

            if (subtitle != null) {
                this.subtitle = subtitle;
            }
        }

        /** Places the control at the end of the row. Replaces any previous one. */
        public void set_suffix (Gtk.Widget widget) {
            if (suffix != null) {
                remove (suffix);
            }
            widget.valign = Gtk.Align.CENTER;
            append (widget);
            suffix = widget;
        }

        /**
         * Marks this setting as one the running system cannot provide.
         *
         * Shown and explained, never hidden: a setting that silently vanishes
         * reads as a bug, and the user cannot tell whether it is missing or
         * simply somewhere else.
         */
        public void set_unavailable (string reason = "unavailable on this system") {
            add_css_class ("centaur-unavailable");
            sensitive = false;
            set_suffix (new Chip (reason, ChipKind.INFO));
        }
    }

    /** A row whose control is a switch. */
    public class ToggleRow : Row {

        public Gtk.Switch toggle { get; private set; }

        public bool active {
            get { return toggle.active; }
            set { toggle.active = value; }
        }

        public ToggleRow (string title, string? subtitle = null) {
            base (title, subtitle);
            toggle = new Gtk.Switch ();
            set_suffix (toggle);
        }

        /** Two-way binding to a boolean key. GSettings stays the writer. */
        public void bind_setting (Settings settings, string key) {
            settings.bind (key, toggle, "active", SettingsBindFlags.DEFAULT);
        }
    }

    /** A row whose control is a slider, with the value shown beside it. */
    public class SliderRow : Row {

        public Gtk.Scale scale { get; private set; }
        private Gtk.Label value_label;
        private string unit;

        public double value {
            get { return scale.get_value (); }
            set { scale.set_value (value); }
        }

        public SliderRow (string title, double min, double max, double step,
                          string unit = "", string? subtitle = null) {
            base (title, subtitle);
            this.unit = unit;

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);

            scale = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, min, max, step) {
                draw_value = false,
                width_request = 180,
            };
            box.append (scale);

            // A slider in a non-obvious unit is unreadable without its value.
            value_label = new Gtk.Label (null);
            value_label.add_css_class ("caption");
            value_label.add_css_class ("mono");
            box.append (value_label);

            scale.value_changed.connect (update_value_label);
            update_value_label ();

            set_suffix (box);
        }

        private void update_value_label () {
            value_label.label = "%.0f%s".printf (scale.get_value (), unit);
        }

        /**
         * Binds to an integer key.
         *
         * Not settings.bind(): the key is an int and Gtk.Adjustment.value is a
         * double, and GSettings refuses a binding whose types disagree. The
         * rounding has to happen somewhere, so it happens here.
         */
        public void bind_setting (Settings settings, string key) {
            scale.set_value ((double) settings.get_int (key));

            scale.value_changed.connect (() => {
                var rounded = (int) Math.round (scale.get_value ());
                if (settings.get_int (key) != rounded) {
                    settings.set_int (key, rounded);
                }
            });

            settings.changed[key].connect (() => {
                var stored = (double) settings.get_int (key);
                if (scale.get_value () != stored) {
                    scale.set_value (stored);
                }
            });
        }
    }

    /** A row whose control is a drop-down over a fixed list of options. */
    public class ComboRow : Row {

        public Gtk.DropDown dropdown { get; private set; }
        private string[] ids;

        public ComboRow (string title, string[] ids, string[] labels,
                         string? subtitle = null) {
            base (title, subtitle);
            this.ids = ids;
            dropdown = new Gtk.DropDown.from_strings (labels);
            set_suffix (dropdown);
        }

        public string selected_id () {
            var index = (int) dropdown.selected;
            return (index >= 0 && index < ids.length) ? ids[index] : "";
        }

        public void select_id (string id) {
            for (int i = 0; i < ids.length; i++) {
                if (ids[i] == id) {
                    dropdown.selected = i;
                    return;
                }
            }
        }

        /**
         * Binds to a string key by id.
         *
         * Not settings.bind(): GSettings binds the drop-down's integer index,
         * which would break the moment the option list is reordered.
         */
        public void bind_setting (Settings settings, string key) {
            select_id (settings.get_string (key));

            dropdown.notify["selected"].connect (() => {
                var id = selected_id ();
                if (id != "" && settings.get_string (key) != id) {
                    settings.set_string (key, id);
                }
            });

            settings.changed[key].connect (() => {
                select_id (settings.get_string (key));
            });
        }
    }
}
