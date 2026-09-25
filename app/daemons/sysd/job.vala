namespace Centaur.Sysd {

    /**
     * A long-running privileged operation, exported on its own object path.
     *
     * The job lives here rather than in the client, so closing the client
     * mid-upgrade does not kill the upgrade and reopening re-attaches by path.
     *
     * Progress stays at -1 until a backend can actually report a percentage.
     * None of the four package managers reports one in a machine-readable way,
     * so today every job is indeterminate -- which is the honest answer. Faking
     * a crawling bar would be worse than showing a spinner.
     */
    [DBus (name = "org.centaur.System1.Job")]
    public class Job : Object {

        private static uint next_id = 0;

        private Subprocess? process = null;
        private Cancellable cancellable = new Cancellable ();
        private string[] argv;
        private uint registration_id = 0;
        private DBusConnection? connection = null;

        [DBus (visible = false)]
        public ObjectPath path { get; private set; }

        private double _progress = -1.0;
        private string _status = "queued";
        private bool _running = false;

        public double progress { get { return _progress; } }
        public string status { owned get { return _status; } }
        public bool running { get { return _running; } }

        public signal void log_line (string line);
        public signal void finished (bool success, string message);

        /** Raised when the job is done and its path may be released. */
        [DBus (visible = false)]
        public signal void completed ();

        public Job (string[] argv) {
            this.argv = argv;
            this.path = new ObjectPath (
                "/org/centaur/System1/Jobs/%u".printf (++next_id));
        }

        [DBus (visible = false)]
        public void export (DBusConnection connection) throws GLib.Error {
            this.connection = connection;
            this.registration_id = connection.register_object (this.path, this);
        }

        [DBus (visible = false)]
        public void unexport () {
            if (connection != null && registration_id != 0) {
                connection.unregister_object (registration_id);
                registration_id = 0;
            }
        }

        public async void cancel () throws GLib.Error {
            if (!_running) {
                return;
            }
            Core.Log.info ("cancelling job %s", path);
            cancellable.cancel ();
            if (process != null) {
                // SIGTERM, not SIGKILL: a package manager interrupted mid-write
                // can leave the database inconsistent, and it knows how to
                // unwind where we do not.
                process.send_signal ((int) Posix.Signal.TERM);
            }
        }

        [DBus (visible = false)]
        public void run () {
            run_async.begin ();
        }

        private async void run_async () {
            _running = true;
            set_status ("running");

            try {
                process = new Subprocess.newv (argv,
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
            } catch (GLib.Error e) {
                fail (@"cannot start $(argv[0]): $(e.message)");
                return;
            }

            var stream = new DataInputStream (process.get_stdout_pipe ());

            try {
                while (true) {
                    var line = yield stream.read_line_async (Priority.DEFAULT, cancellable);
                    if (line == null) {
                        break;
                    }
                    log_line (line);
                }
            } catch (IOError.CANCELLED e) {
                fail ("cancelled");
                return;
            } catch (GLib.Error e) {
                Core.Log.warn ("job %s output ended: %s", path, e.message);
            }

            try {
                yield process.wait_async (null);
            } catch (GLib.Error e) {
                fail (e.message);
                return;
            }

            if (process.get_if_exited () && process.get_exit_status () == 0) {
                _running = false;
                set_status ("finished");
                finished (true, "");
            } else {
                fail ("exit status %d".printf (process.get_exit_status ()));
                return;
            }

            schedule_release ();
        }

        private void fail (string message) {
            _running = false;
            set_status ("failed");
            Core.Log.warn ("job %s failed: %s", path, message);
            finished (false, message);
            schedule_release ();
        }

        private void set_status (string value) {
            _status = value;
            notify_property ("status");
            notify_property ("running");
        }

        /**
         * Keep the object around briefly after finishing.
         *
         * A client that was closed during the job needs to be able to reopen,
         * re-attach and read the outcome. Sixty seconds is long enough for that
         * and short enough not to accumulate.
         */
        private void schedule_release () {
            Timeout.add_seconds (60, () => {
                completed ();
                return Source.REMOVE;
            });
        }
    }
}
