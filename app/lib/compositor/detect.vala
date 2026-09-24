namespace Centaur.Compositor {

    /**
     * Picks a backend for the session we are in.
     *
     * Detection is by environment rather than by probing: SWAYSOCK is set only
     * by sway, and XDG_CURRENT_DESKTOP is set by the session file. A wrong
     * guess here would mean writing config for a compositor that is not
     * running, so the fallback is the one that cannot do harm.
     */
    namespace Detect {

        public Backend create () {
            var sway_sock = Environment.get_variable ("SWAYSOCK");
            if (sway_sock != null && sway_sock != "") {
                Core.Log.debug ("compositor: sway (SWAYSOCK set)");
                return new SwayBackend (sway_sock);
            }

            var desktop = Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? "";
            var session = Environment.get_variable ("XDG_SESSION_DESKTOP") ?? "";
            var haystack = (desktop + " " + session).down ();

            if ("sway" in haystack) {
                // sway is running but did not export SWAYSOCK: nothing we can
                // talk to, so fall through to labwc's config-only behaviour.
                Core.Log.warn ("sway detected but SWAYSOCK unset; IPC unavailable");
            }

            Core.Log.debug ("compositor: labwc (default)");
            return new LabwcBackend ();
        }
    }
}
