namespace Centaur.Sysd {

    [DBus (name = "org.centaur.System1.Packages")]
    public class PackagesService : Object {

        private Polkit polkit;
        private DBusConnection connection;
        private PackageBackend? selected;
        private Job? active_job = null;

        /**
         * Wire name "Backend", matching PackagesIface. The property and the
         * interface have to agree or the client reads a property that is not
         * there.
         */
        public string backend {
            owned get { return selected != null ? selected.name : ""; }
        }

        public signal void updates_changed ();

        public PackagesService (DBusConnection connection, Polkit polkit) {
            this.connection = connection;
            this.polkit = polkit;
            this.selected = PackageBackends.create ();

            if (selected == null) {
                Core.Log.warn ("no supported package manager found");
            } else {
                Core.Log.info ("package backend: %s", selected.name);
            }
        }

        public async HashTable<string, Variant>[] list_updates (
                GLib.BusName sender) throws GLib.Error {
            yield polkit.require (sender, "org.centaur.system1.packages.read");
            var current = require_backend ();

            var output = yield run_capture (current.list_argv (),
                                            current.list_success_codes ());
            return current.parse_updates (output);
        }

        public async ObjectPath check_updates (GLib.BusName sender) throws GLib.Error {
            yield polkit.require (sender, "org.centaur.system1.packages.read");
            var current = require_backend ();

            // Refreshing metadata writes to the package database, so it is a
            // job rather than a plain call even though the user calls it a check.
            return start_job (current.refresh_argv ());
        }

        public async ObjectPath start_update (string[] ids,
                                              GLib.BusName sender) throws GLib.Error {
            yield polkit.require (sender, "org.centaur.system1.packages.update");
            var current = require_backend ();

            if (active_job != null && active_job.running) {
                throw new Core.SystemError.BUSY ("an update is already running");
            }

            foreach (var id in ids) {
                validate_package_name (id);
            }

            return start_job (current.update_argv (ids));
        }

        private ObjectPath start_job (string[] argv) throws GLib.Error {
            var job = new Job (argv);
            job.export (connection);

            job.finished.connect (() => updates_changed ());
            job.completed.connect (() => {
                job.unexport ();
                if (active_job == job) {
                    active_job = null;
                }
            });

            active_job = job;
            job.run ();
            return job.path;
        }

        [DBus (visible = false)]
        private PackageBackend require_backend () throws GLib.Error {
            if (selected == null) {
                throw new Core.SystemError.BACKEND_MISSING (
                    "no supported package manager is installed");
            }
            return selected;
        }

        /**
         * Package names come from a D-Bus caller, so they are untrusted.
         *
         * They are passed as an argv element and never through a shell, so this
         * is defence in depth rather than the only barrier -- but a name
         * starting with '-' would still be read as a flag by the package
         * manager itself, which is reason enough to reject it here.
         */
        private void validate_package_name (string id) throws GLib.Error {
            if (id.length == 0 || id.length > 256) {
                throw new Core.SystemError.INVALID_ARGUMENT ("bad package name");
            }
            if (id.has_prefix ("-")) {
                throw new Core.SystemError.INVALID_ARGUMENT (
                    "package name may not begin with '-'");
            }
            for (var i = 0; i < id.length; i++) {
                var c = id[i];
                var ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                      || (c >= '0' && c <= '9')
                      || c == '-' || c == '_' || c == '.' || c == '+' || c == ':';
                if (!ok) {
                    throw new Core.SystemError.INVALID_ARGUMENT (
                        "illegal character in package name");
                }
            }
        }

        /** Runs argv to completion and returns its stdout. */
        internal static async string run_capture (string[] argv,
                                                  int[] success_codes) throws GLib.Error {
            Subprocess process;
            try {
                process = new Subprocess.newv (argv,
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
            } catch (GLib.Error e) {
                throw new Core.SystemError.BACKEND_MISSING (
                    "cannot run %s: %s".printf (argv[0], e.message));
            }

            string output;
            yield process.communicate_utf8_async (null, null, out output, null);

            var code = process.get_if_exited () ? process.get_exit_status () : -1;
            foreach (var allowed in success_codes) {
                if (code == allowed) {
                    return output ?? "";
                }
            }

            throw new Core.SystemError.FAILED (
                "%s exited with status %d".printf (argv[0], code));
        }
    }
}
