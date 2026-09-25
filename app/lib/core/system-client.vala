namespace Centaur.Core {

    public const string SYSTEM_BUS_NAME = "org.centaur.System1";
    public const string SYSTEM_OBJECT_PATH = "/org/centaur/System1";

    /**
     * Errors centaur-sysd may return.
     *
     * These are the typed errors architecture.md section 9 requires. The UI
     * branches on them to choose between "unavailable on this system", "you
     * were not authorised" and a genuine failure -- three states that must not
     * look alike to the user.
     */
    [DBus (name = "org.centaur.System1.Error")]
    public errordomain SystemError {
        NOT_SUPPORTED,
        UNAUTHORIZED,
        BACKEND_MISSING,
        BUSY,
        INVALID_ARGUMENT,
        FAILED,
    }

    /**
     * Hardware and storage inventory for the Overview page.
     *
     * Everything is a{sv} rather than a struct. Structs are fixed at the
     * interface level, and this data grows every time someone adds a card;
     * a{sv} lets a newer daemon answer an older client without a version bump.
     */
    [DBus (name = "org.centaur.System1.Host")]
    public interface HostIface : Object {
        public abstract async HashTable<string, Variant> get_hardware_info () throws GLib.Error;
        public abstract async HashTable<string, Variant>[] get_storage () throws GLib.Error;
    }

    /**
     * Package updates.
     *
     * CheckUpdates and StartUpdate return an object path, not a result: the
     * work outlives the window that asked for it. See JobIface.
     */
    [DBus (name = "org.centaur.System1.Packages")]
    public interface PackagesIface : Object {
        public abstract async HashTable<string, Variant>[] list_updates () throws GLib.Error;
        public abstract async ObjectPath check_updates () throws GLib.Error;
        public abstract async ObjectPath start_update (string[] ids) throws GLib.Error;

        /** Name of the backend in use: pacman, apt, dnf or zypper. */
        public abstract string backend { owned get; }

        /** Emitted when the cached update list changes. */
        public abstract signal void updates_changed ();
    }

    [DBus (name = "org.centaur.System1.Security")]
    public interface SecurityIface : Object {
        public abstract async HashTable<string, Variant> get_status () throws GLib.Error;
    }

    /**
     * A long-running privileged operation.
     *
     * The job lives in centaur-sysd, so closing the client mid-upgrade does
     * not kill the upgrade; reopening re-attaches by object path.
     */
    [DBus (name = "org.centaur.System1.Job")]
    public interface JobIface : Object {
        public abstract async void cancel () throws GLib.Error;

        /** 0.0 to 1.0, or -1.0 when the backend cannot report progress. */
        public abstract double progress { get; }
        public abstract string status { owned get; }
        public abstract bool running { get; }

        public abstract signal void log_line (string line);
        public abstract signal void finished (bool success, string message);
    }

    /**
     * Convenience constructors for the proxies.
     *
     * Every one of these can fail -- centaur-sysd may not be installed, or the
     * system bus may be unreachable. Callers are expected to catch and render
     * the "unavailable" state rather than propagate.
     */
    namespace SystemClient {

        public async HostIface get_host () throws GLib.Error {
            return yield Bus.get_proxy<HostIface> (
                BusType.SYSTEM, SYSTEM_BUS_NAME, SYSTEM_OBJECT_PATH);
        }

        public async PackagesIface get_packages () throws GLib.Error {
            return yield Bus.get_proxy<PackagesIface> (
                BusType.SYSTEM, SYSTEM_BUS_NAME, SYSTEM_OBJECT_PATH);
        }

        public async SecurityIface get_security () throws GLib.Error {
            return yield Bus.get_proxy<SecurityIface> (
                BusType.SYSTEM, SYSTEM_BUS_NAME, SYSTEM_OBJECT_PATH);
        }

        public async JobIface get_job (ObjectPath path) throws GLib.Error {
            return yield Bus.get_proxy<JobIface> (
                BusType.SYSTEM, SYSTEM_BUS_NAME, path);
        }

        /** Reads a{sv} defensively: a missing or mistyped key is not a crash. */
        public string text (HashTable<string, Variant> table,
                            string key,
                            string fallback = "—") {
            var value = table.lookup (key);
            if (value == null || !value.is_of_type (VariantType.STRING)) {
                return fallback;
            }
            return value.get_string ();
        }

        public int64 number (HashTable<string, Variant> table,
                             string key,
                             int64 fallback = 0) {
            var value = table.lookup (key);
            if (value == null) {
                return fallback;
            }
            if (value.is_of_type (VariantType.INT64))  return value.get_int64 ();
            if (value.is_of_type (VariantType.UINT64)) return (int64) value.get_uint64 ();
            if (value.is_of_type (VariantType.INT32))  return value.get_int32 ();
            if (value.is_of_type (VariantType.UINT32)) return (int64) value.get_uint32 ();
            return fallback;
        }

        public bool flag (HashTable<string, Variant> table,
                          string key,
                          bool fallback = false) {
            var value = table.lookup (key);
            if (value == null || !value.is_of_type (VariantType.BOOLEAN)) {
                return fallback;
            }
            return value.get_boolean ();
        }
    }
}
