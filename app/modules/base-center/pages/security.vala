namespace Centaur.BaseCenter {

    /**
     * Security, Privacy & Software Updates.
     *
     * Reports facts and offers one action. The page renders a judgement about
     * those facts -- "Secure Boot is off" is shown as a warning -- but the
     * daemon does not, because deciding what is acceptable is the user's call
     * and depends on things a daemon cannot see.
     */
    public class SecurityPage : Object, Page {

        public string id { owned get { return "security"; } }
        public string title { owned get { return "Security & Privacy"; } }
        public string icon { owned get { return "security-high-symbolic"; } }
        public string category { owned get { return CATEGORY_SYSTEM; } }

        public string[] keywords {
            owned get {
                return { "security", "privacy", "update", "updates", "upgrade",
                         "package", "packages", "firewall", "encryption", "luks",
                         "tpm", "secure boot", "patch" };
            }
        }

        private Ui.Card status_card;
        private Ui.Card updates_card;
        private Gtk.Button update_button;
        private Gtk.Label updates_summary;
        private Gtk.ProgressBar progress;
        private Gtk.Label progress_label;
        private Gtk.Box updates_list;
        private Core.PackagesIface? packages = null;
        private Core.JobIface? active_job = null;

        public Gtk.Widget create_widget () {
            var box = Layout.page_box ();

            box.append (Layout.heading ("Security, Privacy & Software Updates"));

            status_card = new Ui.Card ("System hardening");
            box.append (status_card);

            box.append (build_updates_card ());

            load_status.begin ();
            load_updates.begin ();

            return Layout.scroller (box);
        }

        private Gtk.Widget build_updates_card () {
            updates_card = new Ui.Card ("Software updates");

            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
                margin_bottom = 8,
            };

            updates_summary = new Gtk.Label ("Checking…") {
                xalign = 0,
                hexpand = true,
            };
            header.append (updates_summary);

            update_button = new Gtk.Button.with_label ("Install updates");
            update_button.add_css_class ("accent");
            update_button.sensitive = false;
            update_button.clicked.connect (() => start_update.begin ());
            header.append (update_button);

            updates_card.add (header);

            // Indeterminate, and honestly so: none of the four package managers
            // reports a machine-readable percentage, so a moving bar would be a
            // fiction. See Job in centaur-sysd.
            progress = new Gtk.ProgressBar () { visible = false };
            updates_card.add (progress);

            progress_label = new Gtk.Label (null) {
                xalign = 0,
                visible = false,
                ellipsize = Pango.EllipsizeMode.END,
            };
            progress_label.add_css_class ("caption");
            progress_label.add_css_class ("mono");
            updates_card.add (progress_label);

            // The list is its own container so a refresh can empty it. Appending
            // straight onto the card would stack a second copy of every package
            // on top of the first each time the list is re-read.
            updates_list = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            updates_card.add (updates_list);

            return updates_card;
        }

        private async void load_status () {
            Core.SecurityIface security;
            try {
                security = yield Core.SystemClient.get_security ();
            } catch (GLib.Error e) {
                status_card.add (unavailable_row ("centaur-sysd is not running"));
                return;
            }

            HashTable<string, Variant> status;
            try {
                status = yield security.get_status ();
            } catch (GLib.Error e) {
                status_card.add (unavailable_row (e.message));
                return;
            }

            var secure_boot = Core.SystemClient.text (status, "secure-boot", "unknown");
            status_card.add (fact_row ("Secure Boot",
                describe_secure_boot (secure_boot),
                secure_boot == "enabled" ? Ui.ChipKind.SUCCESS
                    : secure_boot == "disabled" ? Ui.ChipKind.WARNING
                    : Ui.ChipKind.NEUTRAL,
                secure_boot_label (secure_boot)));

            var encryption = Core.SystemClient.text (status, "disk-encryption", "none");
            status_card.add (fact_row ("Disk encryption",
                encryption == "luks"
                    ? "At least one LUKS volume is in use"
                    : "No encrypted volumes were found",
                encryption == "luks" ? Ui.ChipKind.SUCCESS : Ui.ChipKind.WARNING,
                encryption == "luks" ? "LUKS" : "None"));

            var tpm = Core.SystemClient.flag (status, "tpm");
            status_card.add (fact_row ("TPM",
                tpm ? "A TPM device is present"
                    : "No TPM device was found",
                tpm ? Ui.ChipKind.SUCCESS : Ui.ChipKind.NEUTRAL,
                tpm ? "Present" : "Absent"));

            var firewall = Core.SystemClient.text (status, "firewall", "none");
            status_card.add (fact_row ("Firewall",
                firewall == "none"
                    ? "No firewall tool is installed"
                    : @"Managed by $firewall",
                firewall == "none" ? Ui.ChipKind.WARNING : Ui.ChipKind.INFO,
                firewall == "none" ? "None" : firewall));
        }

        private static string describe_secure_boot (string state) {
            switch (state) {
                case "enabled":  return "The firmware verifies the boot chain";
                case "disabled": return "The firmware is not verifying the boot chain";
                case "not-applicable": return "This system does not boot via UEFI";
                default: return "The Secure Boot state could not be read";
            }
        }

        private static string secure_boot_label (string state) {
            switch (state) {
                case "enabled":  return "On";
                case "disabled": return "Off";
                case "not-applicable": return "Legacy boot";
                default: return "Unknown";
            }
        }

        private async void load_updates () {
            try {
                packages = yield Core.SystemClient.get_packages ();
            } catch (GLib.Error e) {
                updates_summary.label = "centaur-sysd is not running";
                return;
            }

            packages.updates_changed.connect (() => refresh_updates.begin ());
            yield refresh_updates ();
        }

        private async void refresh_updates () {
            if (packages == null) {
                return;
            }

            clear_updates_list ();

            HashTable<string, Variant>[] updates;
            try {
                updates = yield packages.list_updates ();
            } catch (Core.SystemError.BACKEND_MISSING e) {
                updates_summary.label = "No supported package manager is installed";
                return;
            } catch (Core.SystemError.UNAUTHORIZED e) {
                updates_summary.label = "Not authorised to check for updates";
                return;
            } catch (GLib.Error e) {
                updates_summary.label = @"Could not check for updates: $(e.message)";
                return;
            }

            var backend = packages.backend;

            if (updates.length == 0) {
                updates_summary.label = @"The system is up to date ($backend)";
                update_button.sensitive = false;
                return;
            }

            updates_summary.label = updates.length == 1
                ? @"1 update available ($backend)"
                : @"$(updates.length) updates available ($backend)";
            update_button.sensitive = true;

            var shown = 0;
            foreach (var update in updates) {
                if (shown >= 20) {
                    updates_list.append (new Ui.Row (
                        "…and %d more".printf (updates.length - shown)));
                    break;
                }

                var name = Core.SystemClient.text (update, "name");
                var from = Core.SystemClient.text (update, "old-version", "");
                var to = Core.SystemClient.text (update, "new-version", "");

                var detail = (from != "") ? from + " → " + to : to;
                updates_list.append (new Ui.Row (name, detail));
                shown++;
            }
        }

        private void clear_updates_list () {
            Gtk.Widget? child;
            while ((child = updates_list.get_first_child ()) != null) {
                updates_list.remove (child);
            }
        }

        private async void start_update () {
            if (packages == null) {
                return;
            }

            update_button.sensitive = false;
            progress.visible = true;
            progress.pulse ();
            progress_label.visible = true;
            progress_label.label = "Starting…";

            ObjectPath path;
            try {
                path = yield packages.start_update (new string[0]);
            } catch (Core.SystemError.UNAUTHORIZED e) {
                finish_update (false, "Authorisation was declined");
                return;
            } catch (Core.SystemError.BUSY e) {
                finish_update (false, "An update is already running");
                return;
            } catch (GLib.Error e) {
                finish_update (false, e.message);
                return;
            }

            try {
                active_job = yield Core.SystemClient.get_job (path);
            } catch (GLib.Error e) {
                finish_update (false, e.message);
                return;
            }

            // The job outlives this window. Re-attaching by path after a
            // restart is why StartUpdate returns a path rather than a result.
            active_job.log_line.connect (line => {
                progress.pulse ();
                progress_label.label = line;
            });

            active_job.finished.connect ((success, message) => {
                finish_update (success, success ? "Updates installed" : message);
            });
        }

        private void finish_update (bool success, string message) {
            progress.visible = false;
            progress_label.label = message;
            update_button.sensitive = !success;
            active_job = null;

            if (success) {
                refresh_updates.begin ();
            }
        }

        private Ui.Row fact_row (string title, string detail,
                                 Ui.ChipKind kind, string chip_text) {
            var row = new Ui.Row (title, detail);
            row.set_suffix (new Ui.Chip (chip_text, kind));
            return row;
        }

        private Ui.Row unavailable_row (string reason) {
            var row = new Ui.Row ("Security status", reason);
            row.set_unavailable ("unavailable");
            return row;
        }
    }
}
