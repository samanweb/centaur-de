namespace Centaur.Topbar {

    /**
     * The date and time.
     *
     * This is the only timer in the bar, and it wakes on the minute boundary
     * rather than every second: a bar that ticks at 1 Hz keeps the CPU out of
     * its idle states all session for a display that changes once a minute.
     */
    public class ClockIndicator : TextIndicator, Indicator {

        private Context context;
        private uint tick_source = 0;

        public string indicator_id { owned get { return "clock"; } }

        public ClockIndicator (Context context) {
            this.context = context;

            add_css_class ("centaur-indicator");

            context.config.topbar.changed["clock-format"].connect (() => update ());

            update ();

            // Not a destructor: the timeout closure holds a reference to this
            // widget, so a destructor would never run and the clock would keep
            // ticking after its monitor was unplugged. map/unmap is the hook
            // that actually fires, and it stops the timer while hidden too.
            map.connect (start_ticking);
            unmap.connect (stop_ticking);
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
            this.label = now.format (format);
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
