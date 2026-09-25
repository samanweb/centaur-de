namespace Centaur.BackgroundSettings {

    /**
     * centaur-background.
     *
     * Spawned on demand from the launcher and gone when closed. It only
     * writes settings; centaur-bg, which runs all session, does the drawing.
     */
    public class Application : Gtk.Application {

        public Application () {
            Object (application_id: "org.centaur.Background",
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
        Environment.set_prgname ("centaur-background");
        return new Application ().run (args);
    }
}
