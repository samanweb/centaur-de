namespace Centaur.Settingsd {

    /**
     * Puts the saved display layout back at login and on hotplug.
     *
     * The compositor forgets output changes at logout, and plugs a new monitor
     * in with its own defaults. This watches the set of connected monitors
     * and, each time it changes, applies whatever displays.json has for them.
     *
     * Only a change in *which* monitors are connected triggers it. Reacting to
     * every layout change would fight the settings window while the user is
     * trying a new layout, and loop on its own applies.
     */
    public class DisplayApplier : Object {

        private Native.OutputManager? manager = null;
        private string connected = "";

        public void start () {
            manager = Native.OutputManager.connected (on_changed);
            if (manager == null) {
                Core.Log.warn ("no Wayland display; saved display layout not applied");
            }
        }

        private void on_changed (Variant snapshot) {
            var heads = Displays.parse (snapshot);

            var identities = new GenericArray<string> ();
            foreach (var head in heads) {
                identities.add (head.identity);
            }
            // Sorted: the compositor's announcement order is not a property of
            // the set of monitors.
            identities.sort (strcmp);
            var key = string.joinv ("\n", identities.data);
            if (key == connected) {
                return;
            }
            connected = key;

            var wanted = Displays.copy_all (heads);
            if (!new Displays.Store ().restore (wanted)) {
                return;
            }
            Displays.normalize (wanted);

            Core.Log.info ("applying saved layout for %d display(s)", heads.length);
            manager.apply (Displays.build_config (wanted), false, (result) => {
                if (result != "succeeded") {
                    // Leaving the compositor's own layout in place is the safe
                    // failure; nothing is retried, so a bad entry cannot loop.
                    Core.Log.warn ("saved display layout was %s by the compositor", result);
                }
            });
        }
    }
}
