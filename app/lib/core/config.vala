namespace Centaur.Core {

    /**
     * Typed access to the org.centaur.* GSettings schemas.
     *
     * GSettings is the store; this is only a convenience layer over it. Nothing
     * here caches, because every consumer wants the change notification that
     * GSettings already provides.
     */
    public class Config : Object {

        private static Config? instance = null;

        public Settings appearance { get; private set; }
        public Settings topbar { get; private set; }
        public Settings compositor { get; private set; }

        public static unowned Config get_default () {
            if (instance == null) {
                instance = new Config ();
            }
            return instance;
        }

        private Config () {
            this.appearance = new Settings ("org.centaur.appearance");
            this.topbar     = new Settings ("org.centaur.topbar");
            this.compositor = new Settings ("org.centaur.compositor");
        }

        /**
         * The palette to actually load.
         *
         * 'auto' is not a palette -- it resolves to dark or light against the
         * configured schedule. Everything downstream deals in real palettes, so
         * this is the only place that has to know 'auto' exists.
         */
        public string resolved_palette () {
            var mode = appearance.get_string ("colour-mode");
            if (mode != "auto") {
                return mode;
            }

            var now = new DateTime.now_local ();
            var minutes = now.get_hour () * 60 + now.get_minute ();

            var sunrise = parse_time (appearance.get_string ("auto-sunrise"), 7 * 60);
            var sunset  = parse_time (appearance.get_string ("auto-sunset"), 19 * 60);

            // A sunrise later than sunset would mean a schedule crossing
            // midnight; treat the daylight window as the wrapped interval.
            if (sunrise <= sunset) {
                return (minutes >= sunrise && minutes < sunset) ? "light" : "dark";
            }
            return (minutes >= sunrise || minutes < sunset) ? "light" : "dark";
        }

        /**
         * How long until resolved_palette() would answer differently.
         *
         * Clamped to an hour so that a clock jump, a suspend or a malformed key
         * cannot leave a process waiting for a boundary that has already gone
         * past.
         */
        public uint seconds_until_palette_change () {
            var now = new DateTime.now_local ();
            var minutes = now.get_hour () * 60 + now.get_minute ();

            var sunrise = parse_time (appearance.get_string ("auto-sunrise"), 7 * 60);
            var sunset  = parse_time (appearance.get_string ("auto-sunset"), 19 * 60);

            var next = int.MAX;
            foreach (var boundary in new int[] { sunrise, sunset }) {
                var delta = boundary - minutes;
                if (delta <= 0) {
                    delta += 24 * 60;   // it is tomorrow's boundary
                }
                next = int.min (next, delta);
            }

            var seconds = (uint) (next * 60 - now.get_seconds () + 1);
            return uint.min (seconds, 3600);
        }

        /**
         * Minutes since midnight, or the fallback if the value is malformed.
         * A bad key must not stop the desktop from starting.
         */
        private static int parse_time (string value, int fallback) {
            var parts = value.split (":");
            if (parts.length != 2) {
                return fallback;
            }
            var hour = int.parse (parts[0]);
            var minute = int.parse (parts[1]);
            if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
                return fallback;
            }
            return hour * 60 + minute;
        }
    }
}
