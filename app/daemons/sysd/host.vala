namespace Centaur.Sysd {

    /**
     * Hardware and storage inventory for the Overview page.
     *
     * Everything here is read from /proc and /sys, which need no helper tools
     * and no parsing of human-facing output. Storage is the exception: block
     * topology has no clean sysfs answer, so lsblk is asked for JSON.
     */
    [DBus (name = "org.centaur.System1.Host")]
    public class HostService : Object {

        private Polkit polkit;

        public HostService (Polkit polkit) {
            this.polkit = polkit;
        }

        public async HashTable<string, Variant> get_hardware_info (
                GLib.BusName sender) throws GLib.Error {
            yield polkit.require (sender, "org.centaur.system1.host.read");

            var info = new HashTable<string, Variant> (str_hash, str_equal);

            var distro = Core.Distro.get_default ();
            info.insert ("distro-name", new Variant.string (distro.name));
            info.insert ("distro-id", new Variant.string (distro.id));
            info.insert ("distro-family", new Variant.string (distro.family.to_string ()));

            info.insert ("kernel", new Variant.string (read_trimmed ("/proc/sys/kernel/osrelease")));
            info.insert ("hostname", new Variant.string (Environment.get_host_name ()));

            info.insert ("board", new Variant.string (dmi ("board_name")));
            info.insert ("board-vendor", new Variant.string (dmi ("board_vendor")));
            info.insert ("bios-version", new Variant.string (dmi ("bios_version")));
            info.insert ("bios-date", new Variant.string (dmi ("bios_date")));
            info.insert ("product", new Variant.string (dmi ("product_name")));

            info.insert ("cpu-model", new Variant.string (cpu_model ()));
            info.insert ("cpu-threads", new Variant.int64 ((int64) get_num_processors ()));

            info.insert ("memory-total-kb", new Variant.int64 (meminfo ("MemTotal")));
            info.insert ("memory-available-kb", new Variant.int64 (meminfo ("MemAvailable")));

            info.insert ("uptime-seconds", new Variant.int64 (uptime_seconds ()));
            info.insert ("load-average", new Variant.string (load_average ()));

            return info;
        }

        public async HashTable<string, Variant>[] get_storage (
                GLib.BusName sender) throws GLib.Error {
            yield polkit.require (sender, "org.centaur.system1.host.read");

            var output = yield PackagesService.run_capture (
                { "lsblk", "--json", "--bytes", "--output",
                  "NAME,SIZE,FSUSED,FSTYPE,MOUNTPOINT,TYPE,MODEL" },
                { 0 });

            HashTable<string, Variant>[] devices = {};

            var parser = new Json.Parser ();
            parser.load_from_data (output);

            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                return devices;
            }

            var container = root.get_object ();
            if (!container.has_member ("blockdevices")) {
                return devices;
            }

            collect_devices (container.get_array_member ("blockdevices"), ref devices);
            return devices;
        }

        /** lsblk nests partitions under their disk; the page wants both. */
        private void collect_devices (Json.Array nodes,
                                      ref HashTable<string, Variant>[] devices) {
            for (uint i = 0; i < nodes.get_length (); i++) {
                var element = nodes.get_element (i);
                if (element.get_node_type () != Json.NodeType.OBJECT) {
                    continue;
                }

                var node = element.get_object ();
                var device = new HashTable<string, Variant> (str_hash, str_equal);

                device.insert ("name", new Variant.string (json_text (node, "name")));
                device.insert ("type", new Variant.string (json_text (node, "type")));
                device.insert ("fstype", new Variant.string (json_text (node, "fstype")));
                device.insert ("mountpoint", new Variant.string (json_text (node, "mountpoint")));
                device.insert ("model", new Variant.string (json_text (node, "model")));
                device.insert ("size-bytes", new Variant.int64 (json_number (node, "size")));
                device.insert ("used-bytes", new Variant.int64 (json_number (node, "fsused")));

                devices += device;

                if (node.has_member ("children")) {
                    collect_devices (node.get_array_member ("children"), ref devices);
                }
            }
        }

        private static string json_text (Json.Object node, string member) {
            if (!node.has_member (member) || node.get_null_member (member)) {
                return "";
            }
            return node.get_string_member (member) ?? "";
        }

        private static int64 json_number (Json.Object node, string member) {
            if (!node.has_member (member) || node.get_null_member (member)) {
                return 0;
            }
            var value = node.get_member (member);
            if (value.get_value_type () == typeof (string)) {
                return int64.parse (node.get_string_member (member));
            }
            return node.get_int_member (member);
        }

        private static string dmi (string field) {
            return read_trimmed (@"/sys/class/dmi/id/$field");
        }

        private static string cpu_model () {
            string contents;
            try {
                FileUtils.get_contents ("/proc/cpuinfo", out contents);
            } catch (FileError e) {
                return "";
            }

            foreach (var line in contents.split ("\n")) {
                // x86 says "model name"; arm64 says "Model" or nothing useful.
                if (line.has_prefix ("model name") || line.has_prefix ("Model")) {
                    var parts = line.split (":", 2);
                    if (parts.length == 2) {
                        return parts[1].strip ();
                    }
                }
            }
            return "";
        }

        private static int64 meminfo (string field) {
            string contents;
            try {
                FileUtils.get_contents ("/proc/meminfo", out contents);
            } catch (FileError e) {
                return 0;
            }

            foreach (var line in contents.split ("\n")) {
                if (!line.has_prefix (field + ":")) {
                    continue;
                }
                var fields = DnfBackend.split_whitespace (line);
                if (fields.length >= 2) {
                    return int64.parse (fields[1]);
                }
            }
            return 0;
        }

        private static int64 uptime_seconds () {
            var value = read_trimmed ("/proc/uptime");
            var fields = value.split (" ");
            return fields.length > 0 ? (int64) double.parse (fields[0]) : 0;
        }

        private static string load_average () {
            var value = read_trimmed ("/proc/loadavg");
            var fields = value.split (" ");
            if (fields.length >= 3) {
                return @"$(fields[0]) $(fields[1]) $(fields[2])";
            }
            return "";
        }

        private static string read_trimmed (string path) {
            string contents;
            try {
                if (!FileUtils.test (path, FileTest.EXISTS)) {
                    return "";
                }
                FileUtils.get_contents (path, out contents);
                return contents.strip ();
            } catch (FileError e) {
                return "";
            }
        }
    }
}
