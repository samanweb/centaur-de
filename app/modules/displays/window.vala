namespace Centaur.DisplaySettings {

    /**
     * Display settings: arrangement, resolution, refresh rate, scale and
     * orientation for every connected monitor.
     *
     * Edits are made on copies and change nothing until Apply. An applied
     * layout is first tested by the compositor, then applied, then has to be
     * confirmed: a resolution the monitor cannot show leaves the user with a
     * black screen and no way to click Keep, so an unanswered question reverts.
     */
    public class Window : Gtk.ApplicationWindow {

        private const int CONFIRM_SECONDS = 15;

        private const double[] SCALES = { 1.0, 1.25, 1.5, 1.75, 2.0 };
        private const string[] ORIENTATIONS = {
            "Landscape", "Portrait (90°)", "Landscape, upside down (180°)", "Portrait (270°)",
        };

        private Native.OutputManager? manager = null;

        // What the compositor reports, and what the user is editing.
        private Displays.Head[] current = {};
        private Displays.Head[] pending = {};
        private string selected = "";
        private bool busy = false;
        private bool updating = false;   // controls are being set, not changed

        private Gtk.Stack stack;
        private Gtk.Label status_label;
        private Arrangement arrangement;
        private Gtk.Widget display_choice_row;
        private Gtk.DropDown display_choice;
        private Gtk.Label settings_title;
        private Gtk.Switch enabled_switch;
        private Gtk.DropDown resolution;
        private Gtk.DropDown refresh;
        private Gtk.DropDown scale;
        private Gtk.DropDown orientation;
        private Gtk.Widget[] mode_rows = {};
        private Gtk.Button apply_button;
        private Gtk.Button reset_button;

        // What each dropdown position stands for, rebuilt with its model.
        private int[] resolution_sizes = {};   // width, height pairs
        private int[] refresh_modes = {};      // mode indices
        private double[] scale_values = {};
        private int[] orientation_values = {};

        public Window (Gtk.Application application) {
            Object (application: application,
                    title: "Displays",
                    default_width: 720,
                    default_height: 760);

            add_css_class ("centaur-window");
            build ();
            connect_output_manager ();

            // While a new layout waits for Keep, closing the window would skip
            // the revert that protects against a blank screen.
            close_request.connect (() => busy);
        }

        // --- building -----------------------------------------------------

        private void build () {
            var header = new Gtk.HeaderBar ();
            set_titlebar (header);

            stack = new Gtk.Stack ();

            status_label = new Gtk.Label ("Reading displays…") {
                wrap = true,
                justify = Gtk.Justification.CENTER,
                valign = Gtk.Align.CENTER,
                margin_start = 32,
                margin_end = 32,
            };
            status_label.add_css_class ("dim");
            stack.add_named (status_label, "status");

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 16) {
                margin_top = 24,
                margin_bottom = 24,
                margin_start = 24,
                margin_end = 24,
            };

            // Arrangement.
            var arrange_card = card ("Arrangement");
            arrangement = new Arrangement ();
            arrangement.head_selected.connect ((name) => {
                selected = name;
                update_controls ();
            });
            arrangement.head_moved.connect (() => {
                Displays.normalize (pending);
                refresh_all ();
            });
            arrange_card.append (arrangement);
            var hint = new Gtk.Label ("Drag displays to match how they sit on your desk.") {
                xalign = 0,
                margin_top = 8,
            };
            hint.add_css_class ("caption");
            arrange_card.append (hint);
            content.append (arrange_card);

            // Per-display settings.
            var settings_card = card ("");
            settings_title = (Gtk.Label) settings_card.get_first_child ();

            display_choice = new Gtk.DropDown (null, null);
            display_choice.notify["selected"].connect (() => {
                if (updating) {
                    return;
                }
                var index = (int) display_choice.selected;
                if (index >= 0 && index < pending.length) {
                    selected = pending[index].name;
                    queue_refresh ();
                }
            });
            display_choice_row = row ("Display", display_choice);
            settings_card.append (display_choice_row);

            enabled_switch = new Gtk.Switch () { valign = Gtk.Align.CENTER };
            enabled_switch.notify["active"].connect (on_enabled_changed);
            settings_card.append (row ("Use this display", enabled_switch));

            resolution = new Gtk.DropDown (null, null);
            resolution.notify["selected"].connect (on_resolution_changed);
            mode_rows += row ("Resolution", resolution);

            refresh = new Gtk.DropDown (null, null);
            refresh.notify["selected"].connect (on_refresh_changed);
            mode_rows += row ("Refresh rate", refresh);

            scale = new Gtk.DropDown (null, null);
            scale.notify["selected"].connect (on_scale_changed);
            mode_rows += row ("Scale", scale);

            orientation = new Gtk.DropDown (null, null);
            orientation.notify["selected"].connect (on_orientation_changed);
            mode_rows += row ("Orientation", orientation);

            foreach (var mode_row in mode_rows) {
                settings_card.append (mode_row);
            }
            content.append (settings_card);

            var scroller = new Gtk.ScrolledWindow () {
                child = content,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vexpand = true,
            };

            // Actions, pinned below the scrolling content.
            reset_button = new Gtk.Button.with_label ("Reset");
            reset_button.clicked.connect (() => {
                pending = Displays.copy_all (current);
                refresh_all ();
            });
            apply_button = new Gtk.Button.with_label ("Apply");
            apply_button.add_css_class ("accent");
            apply_button.clicked.connect (() => apply_pending.begin ());

            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                halign = Gtk.Align.END,
                margin_top = 12,
                margin_bottom = 12,
                margin_start = 24,
                margin_end = 24,
            };
            actions.append (reset_button);
            actions.append (apply_button);

            var main = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            main.append (scroller);
            main.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            main.append (actions);
            stack.add_named (main, "main");

            stack.visible_child_name = "status";
            set_child (stack);
        }

        private static Gtk.Box card (string heading) {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.add_css_class ("centaur-card");
            var label = new Gtk.Label (heading) { xalign = 0 };
            label.add_css_class ("centaur-card-header");
            box.append (label);
            return box;
        }

        private static Gtk.Widget row (string title, Gtk.Widget control) {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            box.add_css_class ("centaur-row");
            var label = new Gtk.Label (title) {
                xalign = 0,
                hexpand = true,
                valign = Gtk.Align.CENTER,
            };
            label.add_css_class ("centaur-row-title");
            control.valign = Gtk.Align.CENTER;
            box.append (label);
            box.append (control);
            return box;
        }

        // --- the compositor ----------------------------------------------

        private void connect_output_manager () {
            var display = Gdk.Display.get_default ();
            if (display is Gdk.Wayland.Display) {
                unowned Wl.Display wl = ((Gdk.Wayland.Display) display).get_wl_display ();
                manager = Native.OutputManager.for_display ((void*) wl, on_changed);
            }
            if (manager == null) {
                show_status ("Display settings need a Wayland session.");
                return;
            }

            // The protocol is announced asynchronously; a compositor without it
            // simply never answers.
            Timeout.add_seconds (2, () => {
                if (manager != null && !manager.is_ready ()) {
                    show_status ("This compositor does not let applications change the "
                                 + "display layout (wlr-output-management is missing).");
                }
                return Source.REMOVE;
            });
        }

        private void show_status (string message) {
            status_label.label = message;
            stack.visible_child_name = "status";
        }

        private void on_changed (Variant snapshot) {
            var fresh = Displays.parse (snapshot);
            var had_edits = !Displays.all_same (current, pending);
            var same_monitors = same_names (fresh, pending);
            current = fresh;

            // Keep the user's unapplied edits when only the live values moved;
            // start over when a monitor came or went.
            if (!had_edits || !same_monitors || busy) {
                pending = Displays.copy_all (current);
            }

            if (current.length == 0) {
                show_status ("No displays reported.");
                return;
            }
            if (find (pending, selected) == null) {
                selected = first_enabled_name ();
            }
            stack.visible_child_name = "main";
            refresh_all ();
        }

        private static bool same_names (Displays.Head[] a, Displays.Head[] b) {
            if (a.length != b.length) {
                return false;
            }
            for (var i = 0; i < a.length; i++) {
                if (a[i].name != b[i].name) {
                    return false;
                }
            }
            return true;
        }

        private static Displays.Head? find (Displays.Head[] heads, string name) {
            foreach (var head in heads) {
                if (head.name == name) {
                    return head;
                }
            }
            return null;
        }

        private string first_enabled_name () {
            foreach (var head in pending) {
                if (head.enabled) {
                    return head.name;
                }
            }
            return pending.length > 0 ? pending[0].name : "";
        }

        // --- showing state -----------------------------------------------

        private void refresh_all () {
            arrangement.set_heads (pending, selected);
            update_controls ();
        }

        private void update_controls () {
            var head = find (pending, selected);
            if (head == null) {
                return;
            }
            updating = true;

            settings_title.label = head.title;

            string[] names = {};
            var chosen = 0;
            for (var i = 0; i < pending.length; i++) {
                names += @"$(pending[i].name) — $(pending[i].title)";
                if (pending[i].name == head.name) {
                    chosen = i;
                }
            }
            set_options (display_choice, names, chosen);
            display_choice_row.visible = pending.length > 1;

            enabled_switch.active = head.enabled;
            // The last display on cannot be switched off from here.
            enabled_switch.sensitive = !head.enabled || count_enabled () > 1;

            foreach (var mode_row in mode_rows) {
                mode_row.visible = head.enabled;
            }
            if (head.enabled) {
                fill_resolution (head);
                fill_refresh (head);
                fill_scale (head);
                fill_orientation (head);
            }

            var dirty = !Displays.all_same (current, pending);
            apply_button.sensitive = dirty && !busy;
            reset_button.sensitive = dirty && !busy;

            updating = false;
        }

        /**
         * Replaces a dropdown's entries only when they differ, then selects.
         *
         * Swapping the model of a GtkDropDown from inside its own
         * notify::selected -- which is where every edit arrives -- sends GTK
         * into an endless resync between the dropdown and its popup list.
         * Edits are also refreshed from an idle (queue_refresh), but not
         * rebuilding an unchanged list is what removes the hazard, and it
         * spares rebuilding every dropdown on every click.
         */
        private static void set_options (Gtk.DropDown dropdown, string[] labels, uint selected) {
            var model = dropdown.model as Gtk.StringList;
            var same = model != null && model.get_n_items () == labels.length;
            for (var i = 0; same && i < labels.length; i++) {
                same = model.get_string (i) == labels[i];
            }
            if (!same) {
                dropdown.model = new Gtk.StringList (labels);
            }
            if (dropdown.selected != selected) {
                dropdown.selected = selected;
            }
        }

        private uint refresh_source = 0;

        /** Refreshes after the signal that caused it has returned. */
        private void queue_refresh () {
            if (refresh_source != 0) {
                return;
            }
            refresh_source = Idle.add (() => {
                refresh_source = 0;
                refresh_all ();
                return Source.REMOVE;
            });
        }

        private int count_enabled () {
            var count = 0;
            foreach (var head in pending) {
                if (head.enabled) {
                    count++;
                }
            }
            return count;
        }

        /** Distinct sizes, largest first; the monitor's own is marked. */
        private void fill_resolution (Displays.Head head) {
            resolution_sizes = {};
            string[] labels = {};
            var chosen = 0;
            var mode = head.effective_mode ();
            var preferred = head.preferred_mode ();

            var order = new GenericArray<Displays.Mode> ();
            foreach (var candidate in head.modes) {
                var seen = false;
                foreach (var listed in order.data) {
                    if (listed.width == candidate.width && listed.height == candidate.height) {
                        seen = true;
                        break;
                    }
                }
                if (!seen) {
                    order.add (candidate);
                }
            }
            order.sort ((a, b) => {
                var area = (int64) b.width * b.height - (int64) a.width * a.height;
                return area > 0 ? 1 : (area < 0 ? -1 : b.width - a.width);
            });

            foreach (var size in order.data) {
                var label = size.size_label ();
                if (preferred != null && size.width == preferred.width
                    && size.height == preferred.height) {
                    label += "  (Recommended)";
                }
                if (mode != null && size.width == mode.width && size.height == mode.height) {
                    chosen = labels.length;
                }
                labels += label;
                resolution_sizes += size.width;
                resolution_sizes += size.height;
            }
            set_options (resolution, labels, chosen);
        }

        /** Every rate offered at the current size, fastest first. */
        private void fill_refresh (Displays.Head head) {
            refresh_modes = {};
            string[] labels = {};
            var mode = head.effective_mode ();
            if (mode == null) {
                set_options (refresh, labels, 0);
                return;
            }

            int[] indices = {};
            for (var i = 0; i < head.modes.length; i++) {
                if (head.modes[i].width == mode.width && head.modes[i].height == mode.height) {
                    indices += i;
                }
            }
            // Fastest first. A handful of entries: insertion sort is plenty.
            for (var i = 1; i < indices.length; i++) {
                var index = indices[i];
                var j = i - 1;
                while (j >= 0 && head.modes[indices[j]].refresh < head.modes[index].refresh) {
                    indices[j + 1] = indices[j];
                    j--;
                }
                indices[j + 1] = index;
            }

            var chosen = 0;
            foreach (var index in indices) {
                if (head.modes[index] == mode) {
                    chosen = labels.length;
                }
                labels += head.modes[index].refresh_label ();
                refresh_modes += index;
            }
            set_options (refresh, labels, chosen);
            refresh.sensitive = labels.length > 1;
        }

        private void fill_scale (Displays.Head head) {
            scale_values = {};
            string[] labels = {};
            var chosen = -1;
            foreach (var value in SCALES) {
                if (Math.fabs (value - head.scale) < 0.001) {
                    chosen = labels.length;
                }
                scale_values += value;
                labels += "%d%%".printf ((int) Math.round (value * 100));
            }
            // A scale set elsewhere stays selectable rather than being lost.
            if (chosen < 0) {
                chosen = labels.length;
                scale_values += head.scale;
                labels += "%d%%".printf ((int) Math.round (head.scale * 100));
            }
            set_options (scale, labels, chosen);
        }

        private void fill_orientation (Displays.Head head) {
            orientation_values = {};
            string[] labels = {};
            var chosen = -1;
            for (var i = 0; i < ORIENTATIONS.length; i++) {
                if (head.transform == i) {
                    chosen = i;
                }
                orientation_values += i;
                labels += ORIENTATIONS[i];
            }
            // Mirrored transforms (4-7) are kept if something else set them.
            if (chosen < 0) {
                chosen = labels.length;
                orientation_values += head.transform;
                labels += "Mirrored";
            }
            set_options (orientation, labels, chosen);
        }

        // --- editing -----------------------------------------------------

        private Displays.Head? editing () {
            return updating ? null : find (pending, selected);
        }

        private void on_enabled_changed () {
            var head = editing ();
            if (head == null || head.enabled == enabled_switch.active) {
                return;
            }
            head.enabled = enabled_switch.active;
            if (head.enabled) {
                if (head.current < 0) {
                    head.current = head.preferred_index ();
                }
                // A display switched on joins at the right-hand end, where it
                // cannot overlap anything.
                var right = 0;
                foreach (var other in pending) {
                    if (other != head && other.enabled) {
                        right = int.max (right, other.x + other.logical_width);
                    }
                }
                head.x = right;
                head.y = 0;
            }
            Displays.normalize (pending);
            queue_refresh ();
        }

        private void on_resolution_changed () {
            var head = editing ();
            var index = (int) resolution.selected;
            if (head == null || index * 2 + 1 >= resolution_sizes.length) {
                return;
            }
            var old_mode = head.effective_mode ();
            var rate = old_mode != null ? old_mode.refresh : 60000;
            var mode = head.find_mode (resolution_sizes[index * 2],
                                       resolution_sizes[index * 2 + 1], rate);
            if (mode >= 0 && mode != head.current) {
                resize (head, () => { head.current = mode; });
            }
        }

        private void on_refresh_changed () {
            var head = editing ();
            var index = (int) refresh.selected;
            if (head == null || index >= refresh_modes.length) {
                return;
            }
            head.current = refresh_modes[index];
            queue_refresh ();
        }

        private void on_scale_changed () {
            var head = editing ();
            var index = (int) scale.selected;
            if (head == null || index >= scale_values.length) {
                return;
            }
            var value = scale_values[index];
            resize (head, () => { head.scale = value; });
        }

        private void on_orientation_changed () {
            var head = editing ();
            var index = (int) orientation.selected;
            if (head == null || index >= orientation_values.length) {
                return;
            }
            var value = orientation_values[index];
            resize (head, () => { head.transform = value; });
        }

        private delegate void Change ();

        /**
         * Applies a change to a display's size and keeps its neighbours
         * attached: whatever sat against its right or bottom edge moves with
         * that edge, so the layout neither overlaps nor opens a gap.
         */
        private void resize (Displays.Head head, Change change) {
            var old_right = head.x + head.logical_width;
            var old_bottom = head.y + head.logical_height;

            change ();

            var dx = head.x + head.logical_width - old_right;
            var dy = head.y + head.logical_height - old_bottom;
            foreach (var other in pending) {
                if (other == head || !other.enabled) {
                    continue;
                }
                if (other.x >= old_right) {
                    other.x += dx;
                }
                if (other.y >= old_bottom) {
                    other.y += dy;
                }
            }
            Displays.normalize (pending);
            queue_refresh ();
        }

        // --- applying ----------------------------------------------------

        private async string request (Displays.Head[] heads, bool test) {
            var result = "failed";
            manager.apply (Displays.build_config (heads), test, (outcome) => {
                result = outcome;
                Idle.add (request.callback);
            });
            yield;
            return result;
        }

        private async void apply_pending () {
            if (manager == null || busy) {
                return;
            }
            busy = true;
            update_controls ();

            var previous = Displays.copy_all (current);
            var wanted = Displays.copy_all (pending);

            var tested = yield request (wanted, true);
            if (tested != "succeeded") {
                busy = false;
                update_controls ();
                report (tested == "cancelled"
                        ? "The displays changed while applying. Check the settings and try again."
                        : "The displays cannot use these settings together.");
                return;
            }

            var applied = yield request (wanted, false);
            if (applied != "succeeded") {
                busy = false;
                update_controls ();
                report ("The compositor could not apply these settings.");
                return;
            }

            var keep = yield confirm ();
            if (keep) {
                try {
                    new Displays.Store ().save (wanted);
                } catch (GLib.Error e) {
                    report (@"The new layout is in use, but could not be saved: $(e.message)");
                }
            } else {
                var reverted = yield request (previous, false);
                if (reverted != "succeeded") {
                    report ("The previous layout could not be restored.");
                }
                pending = Displays.copy_all (previous);
            }

            busy = false;
            refresh_all ();
        }

        /**
         * "Keep these settings?", reverting on its own after a countdown.
         * Closing the question, or the window, counts as no.
         */
        private async bool confirm () {
            var keep = false;
            var remaining = CONFIRM_SECONDS;

            var dialog = new Gtk.Window () {
                transient_for = this,
                modal = true,
                resizable = false,
                title = "Keep Display Settings?",
                deletable = true,
            };
            dialog.add_css_class ("centaur-window");

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                margin_top = 24,
                margin_bottom = 20,
                margin_start = 24,
                margin_end = 24,
            };
            var heading = new Gtk.Label ("Keep these display settings?") { xalign = 0 };
            heading.add_css_class ("title");
            var countdown = new Gtk.Label ("") { xalign = 0 };
            countdown.add_css_class ("dim");
            box.append (heading);
            box.append (countdown);

            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                halign = Gtk.Align.END,
                margin_top = 8,
            };
            var revert = new Gtk.Button.with_label ("Revert");
            var accept = new Gtk.Button.with_label ("Keep Changes");
            accept.add_css_class ("accent");
            buttons.append (revert);
            buttons.append (accept);
            box.append (buttons);
            dialog.child = box;

            var done = false;
            uint timer = 0;
            SourceFunc finish = confirm.callback;
            Change close = () => {
                if (done) {
                    return;
                }
                done = true;
                if (timer != 0) {
                    Source.remove (timer);
                }
                dialog.destroy ();
                Idle.add ((owned) finish);
            };

            revert.clicked.connect (() => close ());
            accept.clicked.connect (() => {
                keep = true;
                close ();
            });
            dialog.close_request.connect (() => {
                close ();
                return true;
            });

            countdown.label = @"Reverting to the previous settings in $remaining seconds.";
            timer = Timeout.add_seconds (1, () => {
                remaining--;
                if (remaining <= 0) {
                    timer = 0;
                    close ();
                    return Source.REMOVE;
                }
                countdown.label = @"Reverting to the previous settings in $remaining seconds.";
                return Source.CONTINUE;
            });

            dialog.present ();
            accept.grab_focus ();
            yield;
            return keep;
        }

        private void report (string message) {
            var dialog = new Gtk.AlertDialog ("Display settings not applied") {
                detail = message,
            };
            dialog.show (this);
        }
    }
}
