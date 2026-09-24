namespace Centaur.BaseCenter {

    public class Application : Gtk.Application {

        private Window? window = null;

        public Application () {
            Object (application_id: "org.centaur.BaseCenter",
                    flags: ApplicationFlags.DEFAULT_FLAGS);
        }

        public override void startup () {
            base.startup ();
            Ui.Theme.init ();
        }

        public override void activate () {
            if (window == null) {
                window = new Window (this);
            }
            window.present ();
        }
    }

    public static int main (string[] args) {
        Environment.set_prgname ("centaur-base-center");
        return new Application ().run (args);
    }
}
