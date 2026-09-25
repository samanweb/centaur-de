namespace Centaur.Screenshot {

    /**
     * centaur-screenshot.
     *
     *     centaur-screenshot            the capture window
     *     centaur-screenshot --screen   every display, straight away (Print)
     *     centaur-screenshot --display  pick a display to capture
     *     centaur-screenshot --area     drag out a rectangle (Shift+Print)
     *
     * Every screenshot is saved in ~/Pictures/Screenshots and copied to the
     * clipboard, and a card under the topbar says so. The process lives only
     * as long as that takes.
     */
    public class Application : Gtk.Application {

        private bool busy = false;

        public Application () {
            Object (application_id: "org.centaur.Screenshot",
                    flags: ApplicationFlags.HANDLES_COMMAND_LINE);
        }

        public override void startup () {
            base.startup ();
            Ui.Theme.init ();
        }

        /** Also receives a second launch's arguments, e.g. Print pressed twice. */
        public override int command_line (ApplicationCommandLine command_line) {
            var args = command_line.get_arguments ();
            Mode? mode = null;
            foreach (var arg in args[1:args.length]) {
                if (arg.has_prefix ("--")) {
                    mode = Mode.parse (arg.substring (2));
                    if (mode == null) {
                        command_line.printerr ("unknown option %s\n", arg);
                        return 2;
                    }
                }
            }

            if (mode == null) {
                activate ();
            } else {
                capture.begin (mode);
            }
            return 0;
        }

        public override void activate () {
            var window = active_window as Window;
            if (window == null) {
                window = new Window (this);
                window.capture_requested.connect ((mode) => {
                    capture.begin (mode, () => window.destroy ());
                });
            }
            window.present ();
        }

        private async void capture (Mode mode) {
            if (busy) {
                return;   // one selection at a time
            }
            busy = true;
            hold ();

            try {
                var path = yield Capture.take (mode);
                new Toast.saved (this, path).present ();
            } catch (CaptureError.CANCELLED e) {
                // Escape during the selection: nothing to say.
            } catch (GLib.Error e) {
                Core.Log.error ("screenshot failed: %s", e.message);
                new Toast.failed (this, e.message).present ();
            }

            release ();
            busy = false;
        }
    }

    public static int main (string[] args) {
        Environment.set_prgname ("centaur-screenshot");
        return new Application ().run (args);
    }
}
