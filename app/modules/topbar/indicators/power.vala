namespace Centaur.Topbar {

    [DBus (name = "org.freedesktop.login1.Manager")]
    private interface LoginManager : Object {
        public abstract async string can_suspend () throws GLib.Error;
    }

    [DBus (name = "org.freedesktop.systemd1.Manager")]
    private interface SystemdManager : Object {
        public abstract string virtualization { owned get; }
    }

    /**
     * Session and power actions.
     *
     * Everything here goes through systemd-logind rather than through sudo or a
     * setuid helper: logind already owns these decisions and already asks
     * polkit, so Centaur has no business reimplementing the policy.
     */
    public class PowerIndicator : Gtk.Box, Indicator {

        private Gtk.MenuButton button;
        private Gtk.Button suspend_item;

        // Null until probed. Whether suspend is offered is decided once per
        // process; neither answer changes while the session runs.
        private static bool? suspend_supported = null;

        public string indicator_id { owned get { return "power"; } }

        public PowerIndicator () {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

            // GtkMenuButton is final in GTK4, so the indicator holds one
            // rather than being one.
            button = new Gtk.MenuButton () {
                icon_name = "system-shutdown-symbolic",
                tooltip_text = "Session",
            };
            button.add_css_class ("centaur-indicator");
            append (button);

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            box.append (action_button ("Lock", "system-lock-screen-symbolic",
                                       () => lock_screen.begin ()));
            box.append (action_button ("Log Out", "system-log-out-symbolic",
                                       () => run.begin ({ "loginctl", "terminate-session",
                                                          session_id () })));
            box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            suspend_item = action_button ("Suspend", "weather-clear-night-symbolic",
                                          () => suspend.begin ());
            // Hidden until the probe says the machine can come back from it.
            suspend_item.visible = false;
            box.append (suspend_item);
            box.append (action_button ("Restart", "system-reboot-symbolic",
                                       () => run.begin ({ "systemctl", "reboot" })));

            var shutdown = action_button ("Power Off", "system-shutdown-symbolic",
                                          () => run.begin ({ "systemctl", "poweroff" }));
            shutdown.add_css_class ("danger");
            box.append (shutdown);

            var popover = new Gtk.Popover () { has_arrow = false };
            popover.add_css_class ("centaur-topbar-menu");
            popover.set_child (box);
            button.popover = popover;

            Core.Config.get_default ().topbar.changed["suspend-button"].connect (
                () => update_suspend_item ());
            probe_suspend.begin ();
        }

        /**
         * Offer Suspend only where the machine can be expected to wake again.
         *
         * logind's CanSuspend is necessary but not sufficient: it says "yes"
         * whenever the kernel lists any sleep state, including the s2idle
         * that every QEMU/KVM guest has. A guest that enters it usually has no
         * wake source -- the virtual keyboard and mouse cannot raise it -- so
         * it stays frozen until the host resets it, which from inside looks
         * exactly like a crash. So a virtual machine or container does not get
         * the item unless org.centaur.topbar suspend-button says 'always'.
         */
        private async void probe_suspend () {
            if (suspend_supported == null) {
                suspend_supported = yield can_suspend_safely ();
            }
            update_suspend_item ();
        }

        private static async bool can_suspend_safely () {
            try {
                var login = yield Bus.get_proxy<LoginManager> (
                    BusType.SYSTEM, "org.freedesktop.login1", "/org/freedesktop/login1");
                var answer = yield login.can_suspend ();
                // "challenge" means polkit will ask; that is still possible.
                if (answer != "yes" && answer != "challenge") {
                    Core.Log.debug ("logind CanSuspend=%s; Suspend hidden", answer);
                    return false;
                }
            } catch (GLib.Error e) {
                Core.Log.debug ("cannot ask logind about suspend: %s", e.message);
                return false;
            }

            try {
                var systemd = yield Bus.get_proxy<SystemdManager> (
                    BusType.SYSTEM, "org.freedesktop.systemd1", "/org/freedesktop/systemd1");
                var virt = systemd.virtualization;
                if (virt != null && virt != "") {
                    Core.Log.info ("running under %s; Suspend hidden (a guest usually "
                                   + "cannot wake from it)", virt);
                    return false;
                }
            } catch (GLib.Error e) {
                // Without systemd's answer, trust logind's.
                Core.Log.debug ("cannot ask systemd about virtualisation: %s", e.message);
            }
            return true;
        }

        private void update_suspend_item () {
            switch (Core.Config.get_default ().topbar.get_string ("suspend-button")) {
                case "always":
                    suspend_item.visible = true;
                    break;
                case "never":
                    suspend_item.visible = false;
                    break;
                default:
                    suspend_item.visible = suspend_supported == true;
                    break;
            }
        }

        /**
         * Locks first, as every desktop does, so that waking the machine does
         * not hand the session to whoever opens it. swaylock --daemonize
         * returns only once the screen is locked, so there is no race with
         * the suspend. A missing locker is reported and does not block it.
         */
        private async void suspend () {
            yield lock_screen ();
            yield run ({ "systemctl", "suspend" });
        }

        /**
         * The action is a closure rather than an argv captured by one. Vala
         * stores a captured array parameter by pointer, not by copy, so the
         * handler used to keep a pointer to the temporary array literal at the
         * call site -- freed as soon as the menu was built. Every click then
         * handed freed memory to g_spawn_async and the topbar segfaulted,
         * which centaur-session hid by quietly restarting it.
         */
        private Gtk.Button action_button (string label, string icon, owned Action action) {
            var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            content.append (new Gtk.Image.from_icon_name (icon));
            content.append (new Gtk.Label (label) { xalign = 0, hexpand = true });

            var button = new Gtk.Button () { child = content };
            button.add_css_class ("flat");
            button.add_css_class ("centaur-menu-item");
            button.halign = Gtk.Align.FILL;

            button.clicked.connect (() => {
                if (this.button.popover != null) {
                    this.button.popover.popdown ();
                }
                action ();
            });

            return button;
        }

        private delegate void Action ();

        private static string session_id () {
            var id = Environment.get_variable ("XDG_SESSION_ID");
            return (id != null && id != "") ? id : "self";
        }

        /**
         * Lockers that speak ext-session-lock-v1, which labwc and sway both
         * implement, in order of preference. -f/--daemonize returns once the
         * screen is actually locked.
         */
        private const string[] LOCKERS = { "swaylock", "gtklock", "waylock", "hyprlock" };

        /**
         * `loginctl lock-session` only asks whatever locker is listening to
         * logind's Lock signal, and a bare Centaur session has none, so it
         * used to do nothing at all. A locker is run directly instead; the
         * logind request stays as the fallback for a user who has set up
         * swayidle or similar to answer it.
         */
        private async void lock_screen () {
            foreach (var locker in LOCKERS) {
                if (Environment.find_program_in_path (locker) == null) {
                    continue;
                }
                string[] argv = { locker };
                if (locker == "swaylock") {
                    argv = swaylock_argv ();
                } else if (locker == "gtklock") {
                    argv = { "gtklock", "--daemonize" };
                }
                yield run (argv);
                return;
            }

            yield run ({ "loginctl", "lock-session" });
            report ("Cannot lock the screen",
                    "No screen locker is installed. Install swaylock.");
        }

        /**
         * swaylock with Centaur's lock screen, unless the user has their own.
         *
         * The installed swaylock.conf is generated from the design tokens with
         * the default accent. The four accent keys are overridden here with
         * the user's current one -- swaylock applies arguments after the
         * config file -- so changing accent needs no regenerated file.
         */
        private string[] swaylock_argv () {
            string[] argv = { "swaylock", "--daemonize" };

            if (has_personal_swaylock_config ()) {
                return argv;
            }

            var dir = Ui.Theme.theme_dir ();
            var config = dir != null ? Path.build_filename (dir, "swaylock.conf") : null;
            if (config == null || !FileUtils.test (config, FileTest.EXISTS)) {
                // Not installed: at least not swaylock's default white.
                argv += "--color";
                argv += "0b0f14";
                return argv;
            }

            argv += "--config";
            argv += config;

            var accent = accent_hex (dir);
            if (accent != null) {
                foreach (var key in new string[] {
                        "--key-hl-color", "--caps-lock-key-hl-color",
                        "--ring-ver-color", "--text-ver-color" }) {
                    argv += key;
                    argv += accent;
                }
            }
            return argv;
        }

        /** The places swaylock itself looks, in its order. */
        private static bool has_personal_swaylock_config () {
            var home = Environment.get_home_dir ();
            string[] candidates = {
                Path.build_filename (home, ".swaylock", "config"),
                Path.build_filename (Environment.get_user_config_dir (), "swaylock", "config"),
            };
            foreach (var path in candidates) {
                if (FileUtils.test (path, FileTest.EXISTS)) {
                    return true;
                }
            }
            return false;
        }

        /**
         * The user's accent on the dark palette, as swaylock's rrggbb. The lock
         * screen is always dark, so the dark ramp is the one that has been
         * checked for contrast against it.
         */
        private static string? accent_hex (string dir) {
            var accent = Core.Config.get_default ().appearance.get_string ("accent");
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (Path.build_filename (dir, "accent-map.json"));
                var dark = parser.get_root ().get_object ()
                    .get_object_member ("resolved").get_object_member ("dark");
                if (!dark.has_member (accent)) {
                    return null;
                }
                return dark.get_object_member (accent)
                    .get_string_member ("base").replace ("#", "");
            } catch (GLib.Error e) {
                Core.Log.warn ("cannot read accent map: %s", e.message);
                return null;
            }
        }

        /**
         * Runs a command and says so when it fails, instead of the failure
         * vanishing: a denied polkit request or a missing binary should reach
         * the user, not only a log nobody reads.
         */
        private async void run (owned string[] argv) {
            var command = argv[0];
            try {
                var process = new Subprocess.newv (
                    argv, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
                string? errors;
                yield process.communicate_utf8_async (null, null, null, out errors);
                if (!process.get_successful ()) {
                    var detail = errors != null ? errors.strip () : "";
                    Core.Log.error ("%s failed: %s", command, detail);
                    report (@"$command failed", detail != "" ? detail : "Unknown error");
                }
            } catch (GLib.Error e) {
                Core.Log.error ("cannot run %s: %s", command, e.message);
                report (@"Cannot run $command", e.message);
            }
        }

        /**
         * A dialog rather than notify-send: Centaur has no notification
         * daemon yet (centaur-notifyd is Phase 2), so a notification would
         * fail as silently as the action it reports.
         */
        private void report (string summary, string body) {
            var dialog = new Gtk.AlertDialog ("%s", summary) { detail = body };
            dialog.show (get_root () as Gtk.Window);
        }
    }
}
