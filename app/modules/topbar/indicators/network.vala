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

        public abstract ObjectPath specific_object { owned get; }
    }

    [DBus (name = "org.freedesktop.NetworkManager.AccessPoint")]
    private interface AccessPoint : Object {
        public abstract uint8 strength { get; }
    }

    /**
     * An icon for whatever connection is carrying traffic.
     *
     * NetworkManager already decides which connection is primary, including
     * across VPNs and simultaneous interfaces. Reimplementing that judgement
     * here would only produce a second, worse answer.
     *
     * The bar shows the kind of link and, on Wi-Fi, its strength. The
     * connection's name is in the tooltip: it is rarely what the user is
     * looking for when they glance up, and it is the widest thing in the bar.
     */
    public class NetworkIndicator : TextIndicator, Indicator {

        private const uint32 STATE_CONNECTED_GLOBAL = 70;
        private const uint32 STATE_CONNECTED_SITE = 60;

        private NetworkManagerIface? manager = null;

        // Held so strength changes arrive as PropertiesChanged rather than
        // being polled. Replaced whenever the primary connection changes.
        private AccessPoint? access_point = null;
        private string connection_name = "";

        public string indicator_id { owned get { return "network"; } }

        public NetworkIndicator () {
            add_css_class ("centaur-indicator");
            icon_name = "network-offline-symbolic";
            tooltip_text = "No network connection";
            connect_nm.begin ();
        }

        private async void connect_nm () {
            try {
                manager = yield Bus.get_proxy<NetworkManagerIface> (
                    BusType.SYSTEM,
                    "org.freedesktop.NetworkManager",
                    "/org/freedesktop/NetworkManager");
            } catch (GLib.Error e) {
                Core.Log.debug ("no NetworkManager; network indicator hidden: %s", e.message);
                visible = false;
                return;
            }

            ((Object) manager).notify.connect (() => update.begin ());
            yield update ();
        }

        private async void update () {
            if (manager == null) {
                return;
            }

            access_point = null;

            var state = manager.state;
            if (state != STATE_CONNECTED_GLOBAL && state != STATE_CONNECTED_SITE) {
                icon_name = "network-offline-symbolic";
                add_css_class ("warning");
                tooltip_text = "No network connection";
                return;
            }

            remove_css_class ("warning");

            var path = manager.primary_connection;
            // "/" is NetworkManager's way of saying there is no primary
            // connection, and is not a valid object path to proxy.
            if (path == null || path == "/") {
                icon_name = "network-wired-symbolic";
                tooltip_text = "Connected";
                return;
            }

            ActiveConnection active;
            try {
                active = yield Bus.get_proxy<ActiveConnection> (
                    BusType.SYSTEM, "org.freedesktop.NetworkManager", path);
            } catch (GLib.Error e) {
                icon_name = "network-wired-symbolic";
                tooltip_text = "Connected";
                return;
            }

            connection_name = active.id;

            switch (active.connection_type) {
                case "802-11-wireless":
                    yield watch_access_point (active.specific_object);
                    show_wireless ();
                    return;

                case "vpn":
                case "wireguard":
                    icon_name = "network-vpn-symbolic";
                    break;

                case "gsm":
                case "cdma":
                    icon_name = "network-cellular-connected-symbolic";
                    break;

                default:
                    icon_name = "network-wired-symbolic";
                    break;
            }

            tooltip_text = limited ()
                ? @"$connection_name — no internet access"
                : connection_name;
        }

        private async void watch_access_point (ObjectPath? path) {
            if (path == null || path == "/") {
                return;
            }
            try {
                var ap = yield Bus.get_proxy<AccessPoint> (
                    BusType.SYSTEM, "org.freedesktop.NetworkManager", path);
                access_point = ap;
                // The sender is compared rather than `ap` captured: capturing
                // it would make the proxy own a closure that owns the proxy.
                ((Object) ap).notify["strength"].connect ((sender, pspec) => {
                    // A signal from a proxy we have since replaced is stale.
                    if (sender == access_point) {
                        show_wireless ();
                    }
                });
            } catch (GLib.Error e) {
                Core.Log.debug ("cannot read access point %s: %s", path, e.message);
            }
        }

        private void show_wireless () {
            if (access_point == null) {
                icon_name = "network-wireless-signal-good-symbolic";
                tooltip_text = limited ()
                    ? @"$connection_name — no internet access"
                    : connection_name;
                return;
            }

            var strength = access_point.strength;
            icon_name = @"network-wireless-signal-$(signal_name (strength))-symbolic";
            tooltip_text = limited ()
                ? @"$connection_name — no internet access"
                : @"$connection_name — signal $strength%";
        }

        /** Connected to the local network but not beyond it. */
        private bool limited () {
            return manager != null && manager.state == STATE_CONNECTED_SITE;
        }

        /** The thresholds GNOME and NetworkManager's own applet use. */
        private static string signal_name (uint8 strength) {
            if (strength > 80) return "excellent";
            if (strength > 55) return "good";
            if (strength > 30) return "ok";
            if (strength > 5)  return "weak";
            return "none";
        }
    }
}
