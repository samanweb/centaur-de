namespace Centaur.Session {

    /**
     * A supervised child of the session.
     *
     * Restarts are capped rather than unlimited: a module that crashes on start
     * would otherwise be respawned forever, and a fork bomb is a worse failure
     * than a missing topbar.
     */
    private class Child : Object {

        private const int MAX_RESTARTS = 3;
        private const int WINDOW_SECONDS = 60;

        // Plain fields, not construct properties: a string[] as a GObject
        // property has to be marshalled through a boxed type, which Vala
        // supports but has no reason to do for a private helper class.
        public string name;
        private string[] argv;

        private Subprocess? process = null;
        private int restarts = 0;
        private int64 window_started = 0;
        private bool stopping = false;

        public Child (string name, string[] argv) {
            this.name = name;
            this.argv = argv;
        }

        public void start () {
            if (stopping) {
                return;
            }

            try {
                process = new Subprocess.newv (argv, SubprocessFlags.NONE);
            } catch (GLib.Error e) {
                Core.Log.error ("cannot start %s: %s", name, e.message);
                return;
            }

            Core.Log.info ("started %s", name);
            watch.begin ();
        }

        public void stop () {
            stopping = true;
            if (process != null) {
                process.send_signal ((int) Posix.Signal.TERM);
            }
        }

        private async void watch () {
            try {
                yield process.wait_async (null);
            } catch (GLib.Error e) {
                Core.Log.warn ("cannot wait on %s: %s", name, e.message);
                return;
            }

            if (stopping) {
                return;
            }

            var now = get_monotonic_time () / 1000000;
            if (now - window_started > WINDOW_SECONDS) {
                window_started = now;
                restarts = 0;
            }

            restarts++;

            if (restarts > MAX_RESTARTS) {
                // Staying down and saying so beats an invisible restart loop
                // that burns the battery and never recovers.
                Core.Log.error (
                    "%s crashed %d times in %d seconds; leaving it stopped",
                    name, restarts, WINDOW_SECONDS);
                notify_failure ();
                return;
            }

            var delay = (uint) Math.pow (2, restarts - 1);   // 1s, 2s, 4s
            Core.Log.warn ("%s exited; restarting in %us (attempt %d/%d)",
                           name, delay, restarts, MAX_RESTARTS);

            Timeout.add_seconds (delay, () => {
                start ();
                return Source.REMOVE;
            });
        }

        private void notify_failure () {
            try {
                Process.spawn_async (null,
                    { "notify-send", "--urgency=critical",
                      "Centaur", @"$name stopped responding and was not restarted" },
                    null, SpawnFlags.SEARCH_PATH, null, null);
            } catch (SpawnError e) {
                // A missing notification daemon is not worth a second error.
            }
        }
    }

    /**
     * centaur-session.
     *
     * Runs in two modes. Without arguments it is the session entry point named
     * by centaur.desktop: it sets the environment and starts the compositor.
     * With --shell it is what the compositor starts, inside the Wayland
     * session, and supervises the shell processes.
     *
     * The split exists because only the compositor can tell its children which
     * Wayland display to connect to. Starting the topbar from outside would
     * mean guessing at a socket name.
     */
    public class Session : Object {

        private MainLoop loop;
        private Child[] children = {};

        public Session (MainLoop loop) {
            this.loop = loop;
        }

        /** Session entry point: start the compositor and wait for it. */
        public int run_session () {
            Environment.set_variable ("XDG_CURRENT_DESKTOP", "Centaur", true);
            Environment.set_variable ("XDG_SESSION_DESKTOP", "centaur", true);
            Environment.set_variable ("XDG_SESSION_TYPE", "wayland", true);

            // Ask toolkits to use Wayland rather than falling back to XWayland.
            Environment.set_variable ("GDK_BACKEND", "wayland,x11", false);
            Environment.set_variable ("QT_QPA_PLATFORM", "wayland;xcb", false);
            Environment.set_variable ("MOZ_ENABLE_WAYLAND", "1", false);

            var compositor = choose_compositor ();
            if (compositor == null) {
                printerr ("centaur-session: no supported compositor found.\n"
                          + "Install labwc (recommended) or sway.\n");
                return 1;
            }

            string[] argv;
            if (compositor == "labwc") {
                // -S runs a command inside the compositor's session, which is
                // how the shell inherits WAYLAND_DISPLAY.
                argv = { "labwc", "-S", "centaur-session --shell" };
            } else {
                // sway has no equivalent flag; its config's exec lines start the
                // shell. See README.md for the two lines that need adding.
                argv = { "sway" };
            }

            Core.Log.info ("centaur-session %s starting %s",
                           Version.STRING, compositor);

            try {
                var process = new Subprocess.newv (argv, SubprocessFlags.NONE);
                process.wait (null);
                return process.get_if_exited () ? process.get_exit_status () : 1;
            } catch (GLib.Error e) {
                printerr ("centaur-session: cannot start %s: %s\n",
                          compositor, e.message);
                return 1;
            }
        }

        /** Shell mode: supervise the session's own processes. */
        public int run_shell () {
            if (Environment.get_variable ("WAYLAND_DISPLAY") == null) {
                printerr ("centaur-session --shell: no WAYLAND_DISPLAY; "
                          + "this mode is started by the compositor\n");
                return 1;
            }

            children += new Child ("centaur-settingsd",
                                   { find_helper ("centaur-settingsd") });
            children += new Child ("centaur-topbar",
                                   { find_helper ("centaur-topbar") });

            foreach (var child in children) {
                child.start ();
            }

            Unix.signal_add ((int) Posix.Signal.TERM, () => { shutdown (); return Source.REMOVE; });
            Unix.signal_add ((int) Posix.Signal.INT,  () => { shutdown (); return Source.REMOVE; });

            loop.run ();
            return 0;
        }

        private void shutdown () {
            foreach (var child in children) {
                child.stop ();
            }
            loop.quit ();
        }

        private static string? choose_compositor () {
            var requested = Environment.get_variable ("CENTAUR_COMPOSITOR");
            if (requested != null && requested != ""
                && Environment.find_program_in_path (requested) != null) {
                return requested;
            }

            foreach (var candidate in new string[] { "labwc", "sway" }) {
                if (Environment.find_program_in_path (candidate) != null) {
                    return candidate;
                }
            }
            return null;
        }

        /**
         * Finds a Centaur helper.
         *
         * Paths are not compiled in, so an uninstalled build and a --prefix
         * install both work. CENTAUR_LIBEXECDIR is the escape hatch for running
         * straight out of a build directory.
         */
        private static string find_helper (string name) {
            var override_dir = Environment.get_variable ("CENTAUR_LIBEXECDIR");
            if (override_dir != null) {
                var candidate = Path.build_filename (override_dir, name);
                if (FileUtils.test (candidate, FileTest.IS_EXECUTABLE)) {
                    return candidate;
                }
            }

            foreach (var dir in new string[] { "/usr/libexec", "/usr/lib/centaur",
                                               "/usr/local/libexec" }) {
                var candidate = Path.build_filename (dir, name);
                if (FileUtils.test (candidate, FileTest.IS_EXECUTABLE)) {
                    return candidate;
                }
            }

            var in_path = Environment.find_program_in_path (name);
            return in_path ?? name;
        }
    }

    public static int main (string[] args) {
        Environment.set_prgname ("centaur-session");

        var loop = new MainLoop ();
        var session = new Session (loop);

        foreach (var arg in args[1:args.length]) {
            if (arg == "--shell") {
                return session.run_shell ();
            }
            if (arg == "--version") {
                print ("centaur-session %s\n", Version.STRING);
                return 0;
            }
            if (arg == "--help") {
                print ("Usage: centaur-session [--shell]\n\n"
                       + "  (no arguments)  start the Centaur session\n"
                       + "  --shell         supervise the shell; started by the compositor\n");
                return 0;
            }
        }

        return session.run_session ();
    }
}
