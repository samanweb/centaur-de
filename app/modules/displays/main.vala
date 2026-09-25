namespace Centaur.DisplaySettings {

    /**
     * centaur-displays.
     *
     * Spawned on demand from the launcher and gone when closed: nothing about
     * display settings needs to stay resident. Saved layouts are put back at
     * login by centaur-settingsd, not by this.
     */
    public class Application : Gtk.Application {

        public Application () {
            Object (application_id: "org.centaur.Displays",
                    flags: ApplicationFlags.DEFAULT_FLAGS);
        }

        public override void startup () {
            base.startup ();
            Ui.Theme.init ();
        }

        public override void activate () {
            var window = active_window ?? new Window (this);
            window.present ();
        }
    }

    public static int main (string[] args) {
        Environment.set_prgname ("centaur-displays");
        return new Application ().run (args);
    }
}
