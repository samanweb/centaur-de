namespace Centaur.BaseCenter {

    /**
     * System Overview: what this machine is.
     *
     * Everything shown here comes from centaur-sysd. When the daemon is not
     * reachable the page says so once, plainly, rather than filling eight cards
     * with em dashes and leaving the user to guess why.
     */
    public class OverviewPage : Object, Page {

        public string id { owned get { return "overview"; } }
        public string title { owned get { return "Overview"; } }
        public string icon { owned get { return "computer-symbolic"; } }
        public string category { owned get { return CATEGORY_SYSTEM; } }

        public string[] keywords {
            owned get {
                return { "system", "hardware", "cpu", "memory", "ram", "disk",
                         "storage", "kernel", "uptime", "about", "host" };
            }
        }

        private Ui.StatTile kernel_tile;
        private Ui.StatTile uptime_tile;
        private Ui.StatTile load_tile;
        private Ui.MeterRing memory_ring;
        private Gtk.Label memory_detail;
        private Ui.Card host_card;
        private Ui.Card storage_card;
        private Gtk.Label status_label;

        public Gtk.Widget create_widget () {
            var box = Layout.page_box ();

            box.append (Layout.heading ("System Overview"));

            status_label = new Gtk.Label (null) { xalign = 0, visible = false };
            status_label.add_css_class ("centaur-row-subtitle");
            box.append (status_label);

            box.append (build_summary_card ());

            host_card = new Ui.Card ("Host");
            box.append (host_card);

            storage_card = new Ui.Card ("Storage");
            box.append (storage_card);

            load.begin ();

            return Layout.scroller (box);
        }

        private Gtk.Widget build_summary_card () {
            var card = new Ui.Card ("At a glance");

            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 24) {
                margin_top = 8,
            };

            memory_ring = new Ui.MeterRing (110);
            memory_ring.label_text = "—";
            var memory_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            memory_box.append (memory_ring);

            memory_detail = new Gtk.Label ("Memory") {
                halign = Gtk.Align.CENTER,
            };
            memory_detail.add_css_class ("centaur-stat-label");
            memory_box.append (memory_detail);
            row.append (memory_box);

            var tiles = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
                hexpand = true,
                homogeneous = true,
                valign = Gtk.Align.CENTER,
            };

            kernel_tile = new Ui.StatTile ("Kernel");
            uptime_tile = new Ui.StatTile ("Uptime");
            load_tile   = new Ui.StatTile ("Load average");

            tiles.append (kernel_tile);
            tiles.append (uptime_tile);
            tiles.append (load_tile);
            row.append (tiles);

            card.add (row);
            return card;
        }

        private async void load () {
            Core.HostIface host;
            try {
                host = yield Core.SystemClient.get_host ();
            } catch (GLib.Error e) {
                unavailable ("centaur-sysd is not running, so system information "
                             + "cannot be read. Try: systemctl start centaur-sysd");
                return;
            }

            try {
                var info = yield host.get_hardware_info ();
                fill_summary (info);
                fill_host (info);
            } catch (GLib.Error e) {
                unavailable (@"Could not read hardware information: $(e.message)");
                return;
            }

            try {
                var devices = yield host.get_storage ();
                fill_storage (devices);
            } catch (GLib.Error e) {
                storage_card.add (new Ui.Row ("Storage unavailable", e.message));
            }
        }

        private void unavailable (string message) {
            status_label.label = message;
            status_label.visible = true;
        }

        private void fill_summary (HashTable<string, Variant> info) {
            kernel_tile.value = Core.SystemClient.text (info, "kernel");
            uptime_tile.value = format_uptime (
                Core.SystemClient.number (info, "uptime-seconds"));

            var load = Core.SystemClient.text (info, "load-average", "");
            load_tile.value = (load != "") ? load.split (" ")[0] : "—";

            var total = Core.SystemClient.number (info, "memory-total-kb");
            var available = Core.SystemClient.number (info, "memory-available-kb");

            if (total > 0) {
                var used = total - available;
                memory_ring.fraction = (double) used / (double) total;
                memory_ring.label_text = "%d%%".printf (
                    (int) Math.round (100.0 * used / total));
                memory_detail.label = "Memory · %s of %s".printf (
                    format_size (used * 1024), format_size (total * 1024));
            }
        }

        private void fill_host (HashTable<string, Variant> info) {
            add_fact (host_card, "Operating system",
                      Core.SystemClient.text (info, "distro-name"));
            add_fact (host_card, "Host name",
                      Core.SystemClient.text (info, "hostname"));
            add_fact (host_card, "Processor",
                      Core.SystemClient.text (info, "cpu-model"));
            add_fact (host_card, "Threads",
                      Core.SystemClient.number (info, "cpu-threads").to_string ());

            var board = Core.SystemClient.text (info, "board", "");
            var vendor = Core.SystemClient.text (info, "board-vendor", "");
            if (board != "" || vendor != "") {
                add_fact (host_card, "Mainboard", @"$vendor $board".strip ());
            }

            var bios = Core.SystemClient.text (info, "bios-version", "");
            var bios_date = Core.SystemClient.text (info, "bios-date", "");
            if (bios != "") {
                add_fact (host_card, "Firmware",
                          bios_date != "" ? @"$bios ($bios_date)" : bios);
            }
        }

        private void fill_storage (HashTable<string, Variant>[] devices) {
            var shown = 0;

            foreach (var device in devices) {
                var type = Core.SystemClient.text (device, "type", "");
                var mount = Core.SystemClient.text (device, "mountpoint", "");

                // Unmounted partitions and loop devices are noise on a page
                // whose question is "how much room is left".
                if (mount == "" || type == "loop") {
                    continue;
                }

                var size = Core.SystemClient.number (device, "size-bytes");
                var used = Core.SystemClient.number (device, "used-bytes");
                var name = Core.SystemClient.text (device, "name", "");
                var fstype = Core.SystemClient.text (device, "fstype", "");

                var row = new Ui.Row (mount, @"/dev/$name · $fstype");

                if (size > 0) {
                    var bar = new Gtk.ProgressBar () {
                        fraction = (double) used / (double) size,
                        width_request = 160,
                        valign = Gtk.Align.CENTER,
                        show_text = false,
                    };
                    var detail = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                    detail.append (bar);

                    var caption = new Gtk.Label (
                        "%s of %s".printf (format_size (used), format_size (size)));
                    caption.add_css_class ("caption");
                    caption.add_css_class ("mono");
                    detail.append (caption);

                    row.set_suffix (detail);
                }

                storage_card.add (row);
                shown++;
            }

            if (shown == 0) {
                storage_card.add (new Ui.Row ("No mounted filesystems found"));
            }
        }

        private void add_fact (Ui.Card card, string title, string value) {
            if (value == "" || value == "—") {
                return;
            }
            var row = new Ui.Row (title);
            var label = new Gtk.Label (value);
            label.add_css_class ("mono");
            label.add_css_class ("dim");
            label.ellipsize = Pango.EllipsizeMode.END;
            label.max_width_chars = 48;
            row.set_suffix (label);
            card.add (row);
        }

        private static string format_uptime (int64 seconds) {
            if (seconds <= 0) {
                return "—";
            }
            var days = seconds / 86400;
            var hours = (seconds % 86400) / 3600;
            var minutes = (seconds % 3600) / 60;

            if (days > 0) {
                return @"$(days)d $(hours)h";
            }
            if (hours > 0) {
                return @"$(hours)h $(minutes)m";
            }
            return @"$(minutes)m";
        }

        private static string format_size (int64 bytes) {
            if (bytes < 0) {
                return "—";
            }
            return GLib.format_size ((uint64) bytes);
        }
    }
}
