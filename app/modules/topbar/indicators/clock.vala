namespace Centaur.Topbar {

    /**
     * The date and time, with a calendar a click away.
     *
     * This is the only timer in the bar, and it wakes on the minute boundary
     * rather than every second: a bar that ticks at 1 Hz keeps the CPU out of
     * its idle states all session for a display that changes once a minute.
     *
     * The calendar is built on first open, never at construction, like every
     * other popover in the bar.
     */
    public class ClockIndicator : Gtk.Box, Indicator {

        private Context context;
        private uint tick_source = 0;

        private Gtk.MenuButton button;
        private Gtk.Label caption;
        private Gtk.Calendar? calendar = null;
        private Gtk.Label? heading = null;

        public string indicator_id { owned get { return "clock"; } }

        public ClockIndicator (Context context) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

            this.context = context;

            caption = new Gtk.Label ("");

            // GtkMenuButton is final in GTK4, so the indicator holds one
            // rather than being one.
            button = new Gtk.MenuButton () { child = caption };
            button.add_css_class ("centaur-indicator");
            button.add_css_class ("centaur-clock");
            button.set_create_popup_func (build_popover);
            append (button);

            context.config.topbar.changed["clock-format"].connect (() => update ());

            update ();

            // Not a destructor: the timeout closure holds a reference to this
            // widget, so a destructor would never run and the clock would keep
            // ticking after its monitor was unplugged. map/unmap is the hook
            // that actually fires, and it stops the timer while hidden too.
            map.connect (start_ticking);
            unmap.connect (stop_ticking);
        }

        /**
         * Called by GtkMenuButton on the first opening only: once a popover
         * exists it is reused.
         */
        private void build_popover (Gtk.MenuButton menu_button) {
            heading = new Gtk.Label ("") { xalign = 0 };
            heading.add_css_class ("centaur-calendar-heading");

            calendar = new Gtk.Calendar ();
            calendar.add_css_class ("centaur-calendar");

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.append (heading);
            box.append (calendar);

            var popover = new Gtk.Popover () { child = box, has_arrow = false };
            popover.add_css_class ("centaur-topbar-menu");
            popover.show.connect (show_today);
            menu_button.popover = popover;
        }

        /** Always opens on today, whatever month was browsed to last time. */
        private void show_today () {
            var now = new DateTime.now_local ();
            heading.label = now.format ("%A, %-d %B %Y");
#if GTK_4_20
            calendar.set_date (now);
#else
            // GTK before 4.20 has only the older name.
            calendar.select_day (now);
#endif
        }

        private void start_ticking () {
            if (tick_source == 0) {
                update ();
                schedule_next_tick ();
            }
        }

        private void stop_ticking () {
            if (tick_source != 0) {
                Source.remove (tick_source);
                tick_source = 0;
            }
        }

        private void update () {
            var format = context.config.topbar.get_string ("clock-format");
            var now = new DateTime.now_local ();
            caption.label = now.format (format);
            button.tooltip_text = now.format ("%A, %-d %B %Y");
        }

        private void schedule_next_tick () {
            var now = new DateTime.now_local ();
            // Land just after the boundary, never just before it.
            var seconds = 60 - now.get_second () % 60;

            tick_source = Timeout.add_seconds ((uint) seconds, () => {
                tick_source = 0;
                update ();
                schedule_next_tick ();
                return Source.REMOVE;
            });
        }
    }
}
