namespace Centaur.Topbar {

    [DBus (name = "org.freedesktop.NetworkManager")]
    private interface NetworkManagerIface : Object {
        public abstract uint32 state { get; }
        public abstract ObjectPath primary_connection { owned get; }
    }

    [DBus (name = "org.freedesktop.NetworkManager.Connection.Active")]
    private interface ActiveConnection : Object {
        public abstract string id { owned get; }

        // `type` would generate centaur_topbar_active_connection_get_type(),
        // which collides with the GType function of the same name, so the Vala
        // name differs from the D-Bus one.
        [DBus (name = "Type")]
        public abstract string connection_type { owned get; }
    }

    /**
     * The name of whatever connection is carrying traffic.
     *
     * NetworkManager already decides which connection is primary, including
     * across VPNs and simultaneous interfaces. Reimplementing that judgement
     * here would only produce a second, worse answer.
     */
    public class NetworkIndicator : TextIndicator, Indicator {

        private const uint32 STATE_CONNECTED_GLOBAL = 70;
        private const uint32 STATE_CONNECTED_SITE = 60;

        private NetworkManagerIface? manager = null;

        public string indicator_id { owned get { return "network"; } }

        public NetworkIndicator () {
            add_css_class ("centaur-indicator");
            label = "offline";
            connect_nm.begin ();
        }

        private async void connect_nm () {
            try {
                manager = yield Bus.get_proxy<NetworkManagerIface> (
                    BusType.SYSTEM,
                    "org.freedesktop.NetworkManager",
                    "/org/freedesktop/NetworkManager");
            } catch (GLib.Error e) {
                Core.Log.debug ("no NetworkManager; network indicator idle: %s", e.message);
                label = "—";
                return;
            }

            ((Object) manager).notify.connect (() => update.begin ());
            yield update ();
        }

        private async void update () {
            if (manager == null) {
                return;
            }

            var state = manager.state;
            if (state != STATE_CONNECTED_GLOBAL && state != STATE_CONNECTED_SITE) {
                label = "offline";
                add_css_class ("warning");
                tooltip_text = "No network connection";
                return;
            }

            remove_css_class ("warning");

            var path = manager.primary_connection;
            // "/" is NetworkManager's way of saying there is no primary
            // connection, and is not a valid object path to proxy.
            if (path == null || path == "/") {
                label = "connected";
                tooltip_text = null;
                return;
            }

            try {
                var active = yield Bus.get_proxy<ActiveConnection> (
                    BusType.SYSTEM, "org.freedesktop.NetworkManager", path);
                label = active.id;
                tooltip_text = @"$(active.id) ($(active.connection_type))";
            } catch (GLib.Error e) {
                label = "connected";
                tooltip_text = null;
            }
        }
    }
}
