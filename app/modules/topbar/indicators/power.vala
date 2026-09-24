namespace Centaur.Topbar {

    /**
     * Session and power actions.
     *
     * Everything here goes through systemd-logind rather than through sudo or a
     * setuid helper: logind already owns these decisions and already asks
     * polkit, so Centaur has no business reimplementing the policy.
     */
    public class PowerIndicator : Gtk.MenuButton, Indicator {

        public string indicator_id { owned get { return "power"; } }

        public PowerIndicator () {
            add_css_class ("centaur-indicator");
            add_css_class ("flat");
            icon_name = "system-shutdown-symbolic";
            tooltip_text = "Session";

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            box.append (action_button ("Lock", { "loginctl", "lock-session" }));
            box.append (action_button ("Log out", { "loginctl", "terminate-session",
                                                    session_id () }));
            box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            box.append (action_button ("Suspend", { "systemctl", "suspend" }));
            box.append (action_button ("Restart", { "systemctl", "reboot" }));

            var shutdown = action_button ("Power off", { "systemctl", "poweroff" });
            shutdown.add_css_class ("danger");
            box.append (shutdown);

            var popover = new Gtk.Popover ();
            popover.set_child (box);
            this.popover = popover;
        }

        private Gtk.Button action_button (string label, string[] argv) {
            var button = new Gtk.Button.with_label (label);
            button.add_css_class ("flat");
            button.halign = Gtk.Align.FILL;

            button.clicked.connect (() => {
                if (this.popover != null) {
                    this.popover.popdown ();
                }
                run (argv);
            });

            return button;
        }

        private static string session_id () {
            var id = Environment.get_variable ("XDG_SESSION_ID");
            return (id != null && id != "") ? id : "self";
        }

        private static void run (string[] argv) {
            try {
                Process.spawn_async (null, argv, null,
                                     SpawnFlags.SEARCH_PATH, null, null);
            } catch (SpawnError e) {
                Core.Log.error ("cannot run %s: %s", argv[0], e.message);
            }
        }
    }
}
