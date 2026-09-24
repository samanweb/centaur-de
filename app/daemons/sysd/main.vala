namespace Centaur.Sysd {

    /**
     * centaur-sysd: the one privileged process in Centaur.
     *
     * It links no UI. Root never maps GTK, Pango or a font cache here. The only
     * dependencies are GLib, GIO and json-glib, which is what makes the
     * hardening in the systemd unit meaningful.
     */
    public class Daemon : Object {

        private MainLoop loop;
        private uint owner_id = 0;
        private uint[] registrations = {};

        public Daemon (MainLoop loop) {
            this.loop = loop;
        }

        public void start () {
            owner_id = Bus.own_name (
                BusType.SYSTEM,
                Core.SYSTEM_BUS_NAME,
                BusNameOwnerFlags.NONE,
                on_bus_acquired,
                on_name_acquired,
                on_name_lost);
        }

        private void on_bus_acquired (DBusConnection connection, string name) {
            var polkit = new Polkit (connection);

            try {
                // Three interfaces on one object path: the grouping
                // architecture.md section 6.2 describes, without three paths to
                // keep in step.
                registrations += connection.register_object (
                    Core.SYSTEM_OBJECT_PATH, new HostService (polkit));
                registrations += connection.register_object (
                    Core.SYSTEM_OBJECT_PATH, new PackagesService (connection, polkit));
                registrations += connection.register_object (
                    Core.SYSTEM_OBJECT_PATH, new SecurityService (polkit));
            } catch (GLib.Error e) {
                Core.Log.error ("cannot export objects: %s", e.message);
                loop.quit ();
            }
        }

        private void on_name_acquired (DBusConnection connection, string name) {
            Core.Log.info ("centaur-sysd %s ready on %s", Version.STRING, name);
        }

        private void on_name_lost (DBusConnection? connection, string name) {
            // Losing the name means another instance took over, or the bus went
            // away. Either way this process has nothing left to do.
            Core.Log.error ("lost the name %s; exiting", name);
            loop.quit ();
        }
    }

    public static int main (string[] args) {
        Environment.set_prgname ("centaur-sysd");

        if (Posix.geteuid () != 0) {
            printerr ("centaur-sysd must run as root; it is started by systemd\n");
            return 1;
        }

        var loop = new MainLoop ();

        var daemon = new Daemon (loop);
        daemon.start ();

        // systemd sends SIGTERM on stop. Exiting the loop rather than dying
        // lets in-flight D-Bus replies flush.
        Unix.signal_add ((int) Posix.Signal.TERM, () => { loop.quit (); return Source.REMOVE; });
        Unix.signal_add ((int) Posix.Signal.INT,  () => { loop.quit (); return Source.REMOVE; });

        loop.run ();
        return 0;
    }
}
