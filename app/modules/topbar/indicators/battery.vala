namespace Centaur.Topbar {

    [DBus (name = "org.freedesktop.UPower.Device")]
    private interface UPowerDevice : Object {
        public abstract double percentage { get; }
        public abstract uint32 state { get; }
        public abstract bool is_present { get; }
        public abstract uint32 type { get; }
        public abstract int64 time_to_empty { get; }
    }

    /**
     * Battery level, from UPower's aggregate DisplayDevice.
     *
     * The DisplayDevice is UPower's own summary of whatever power sources
     * exist, so a laptop with two batteries and a desktop with none both work
     * without this knowing anything about the hardware.
     */
    public class BatteryIndicator : TextIndicator, Indicator {

        private const uint32 STATE_CHARGING = 1;
        private const uint32 STATE_FULLY_CHARGED = 4;

        private UPowerDevice? device = null;

        public string indicator_id { owned get { return "battery"; } }

        public BatteryIndicator () {
            add_css_class ("centaur-indicator");
            visible = false;
            connect_upower.begin ();
        }

        private async void connect_upower () {
            try {
                device = yield Bus.get_proxy<UPowerDevice> (
                    BusType.SYSTEM,
                    "org.freedesktop.UPower",
                    "/org/freedesktop/UPower/devices/DisplayDevice");
            } catch (GLib.Error e) {
                Core.Log.debug ("no UPower; battery indicator hidden: %s", e.message);
                return;
            }

            // Proxy properties raise notify from PropertiesChanged, so this is
            // a subscription rather than a poll.
            ((Object) device).notify.connect (() => update ());
            update ();
        }

        private void update () {
            if (device == null) {
                visible = false;
                return;
            }

            // A desktop reports a DisplayDevice that is not present.
            if (!device.is_present) {
                visible = false;
                return;
            }

            visible = true;

            var percent = (int) Math.round (device.percentage);
            var state = device.state;

            var prefix = "";
            if (state == STATE_CHARGING || state == STATE_FULLY_CHARGED) {
                prefix = "⚡ ";   // charging
            }

            this.label = @"$prefix$percent%";

            // Colour reinforces; the number carries the message on its own.
            remove_css_class ("warning");
            remove_css_class ("danger");
            if (state != STATE_CHARGING && state != STATE_FULLY_CHARGED) {
                if (percent <= 10) {
                    add_css_class ("danger");
                } else if (percent <= 25) {
                    add_css_class ("warning");
                }
            }

            tooltip_text = describe (state, percent);
        }

        private string describe (uint32 state, int percent) {
            if (state == STATE_FULLY_CHARGED) {
                return "Battery fully charged";
            }
            if (state == STATE_CHARGING) {
                return @"Charging, $percent%";
            }

            var remaining = device.time_to_empty;
            if (remaining > 0) {
                var hours = remaining / 3600;
                var minutes = (remaining % 3600) / 60;
                return @"$percent% — about $(hours)h $(minutes)m remaining";
            }
            return @"$percent% remaining";
        }
    }
}
