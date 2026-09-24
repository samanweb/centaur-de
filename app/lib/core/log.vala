namespace Centaur.Core {

    /**
     * Logging helpers.
     *
     * Every Centaur process logs through these so that output is uniform in
     * the journal. Debug output is off unless G_MESSAGES_DEBUG names our
     * domain, so a shipped session is quiet by default.
     */
    namespace Log {

        private const string DOMAIN = "centaur";

        public void debug (string format, ...) {
            GLib.logv (DOMAIN, GLib.LogLevelFlags.LEVEL_DEBUG, format, va_list ());
        }

        public void info (string format, ...) {
            GLib.logv (DOMAIN, GLib.LogLevelFlags.LEVEL_INFO, format, va_list ());
        }

        public void warn (string format, ...) {
            GLib.logv (DOMAIN, GLib.LogLevelFlags.LEVEL_WARNING, format, va_list ());
        }

        /**
         * A serious but survivable problem.
         *
         * LEVEL_CRITICAL, not LEVEL_ERROR: GLib treats LEVEL_ERROR as fatal and
         * aborts the process, which is not what a failed CSS load deserves.
         */
        public void error (string format, ...) {
            GLib.logv (DOMAIN, GLib.LogLevelFlags.LEVEL_CRITICAL, format, va_list ());
        }
    }
}
