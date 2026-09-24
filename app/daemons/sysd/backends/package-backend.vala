namespace Centaur.Sysd {

    /**
     * One distribution's package manager.
     *
     * This is where the four distro families differ, and it is the only place
     * in Centaur that knows their names. Everything above centaur-sysd sees one
     * interface.
     *
     * Implementations must not shell out through sh. Every command is an argv
     * array so that a package name can never become a second command.
     */
    public interface PackageBackend : Object {

        public abstract string name { owned get; }

        /** True when this backend's tool is actually installed. */
        public abstract bool available ();

        /** argv that lists pending updates without changing anything. */
        public abstract string[] list_argv ();

        /**
         * Exit codes that mean success for the list command.
         *
         * dnf returns 100 when updates are available, which is not a failure.
         */
        public abstract int[] list_success_codes ();

        /** Parses that command's output into one a{sv} per update. */
        public abstract HashTable<string, Variant>[] parse_updates (string output);

        /** argv that performs the upgrade. */
        public abstract string[] update_argv (string[] ids);

        /**
         * argv that refreshes package metadata.
         *
         * On the interface rather than in a switch inside PackagesService,
         * because which command is safe to run is exactly the distro knowledge
         * that is supposed to stop at this boundary.
         */
        public abstract string[] refresh_argv ();

        protected static HashTable<string, Variant> make_update (
                string name, string old_version, string new_version, string source) {
            var table = new HashTable<string, Variant> (str_hash, str_equal);
            table.insert ("name", new Variant.string (name));
            table.insert ("old-version", new Variant.string (old_version));
            table.insert ("new-version", new Variant.string (new_version));
            table.insert ("source", new Variant.string (source));
            return table;
        }
    }

    /** Arch: pacman -Qu, upgraded with pacman -Syu. */
    public class PacmanBackend : Object, PackageBackend {

        public string name { owned get { return "pacman"; } }

        public bool available () {
            return Environment.find_program_in_path ("pacman") != null;
        }

        /**
         * checkupdates, from pacman-contrib, syncs into a temporary database
         * and prints the same "name old -> new" format as pacman -Qu.
         */
        private static bool has_checkupdates () {
            return Environment.find_program_in_path ("checkupdates") != null;
        }

        public string[] list_argv () {
            if (has_checkupdates ()) {
                return { "checkupdates" };
            }
            // -Qu reads the local database only; it never hits the network.
            return { "pacman", "-Qu" };
        }

        public int[] list_success_codes () {
            // pacman exits 1 with nothing to upgrade; checkupdates exits 2.
            return { 0, 1, 2 };
        }

        /**
         * Refreshing on Arch is checkupdates or nothing.
         *
         * `pacman -Sy` is deliberately NOT used. Syncing the database without
         * upgrading in the same transaction leaves the system in the partial
         * upgrade state that breaks Arch installs, and a settings window is the
         * last place that should do it silently. Without pacman-contrib the
         * refresh degrades to reading the local database, which is honest: it
         * reports what is known rather than risking the machine to learn more.
         */
        public string[] refresh_argv () {
            return list_argv ();
        }

        public HashTable<string, Variant>[] parse_updates (string output) {
            HashTable<string, Variant>[] updates = {};

            foreach (var line in output.split ("\n")) {
                // "name 1.2.3-1 -> 1.2.4-1"
                var trimmed = line.strip ();
                if (trimmed == "" || !(" -> " in trimmed)) {
                    continue;
                }

                var halves = trimmed.split (" -> ", 2);
                var left = halves[0].strip ().split (" ");
                if (left.length < 2) {
                    continue;
                }

                updates += PackageBackend.make_update (
                    left[0], left[1], halves[1].strip (), "pacman");
            }

            return updates;
        }

        public string[] update_argv (string[] ids) {
            // Partial upgrades are unsupported on Arch and break systems, so
            // named packages are deliberately ignored: it is always a full -Syu.
            return { "pacman", "-Syu", "--noconfirm" };
        }
    }

    /** Debian and derivatives: apt list --upgradable, upgraded with apt-get. */
    public class AptBackend : Object, PackageBackend {

        public string name { owned get { return "apt"; } }

        public bool available () {
            return Environment.find_program_in_path ("apt-get") != null;
        }

        public string[] list_argv () {
            return { "apt", "list", "--upgradable" };
        }

        public int[] list_success_codes () {
            return { 0 };
        }

        public HashTable<string, Variant>[] parse_updates (string output) {
            HashTable<string, Variant>[] updates = {};

            foreach (var line in output.split ("\n")) {
                // "name/repo 1.2.4 amd64 [upgradable from: 1.2.3]"
                var trimmed = line.strip ();
                if (trimmed == "" || !("/" in trimmed) || !("upgradable from:" in trimmed)) {
                    continue;
                }

                var fields = trimmed.split (" ");
                if (fields.length < 2) {
                    continue;
                }

                var name = fields[0].split ("/")[0];
                var repo = fields[0].split ("/").length > 1 ? fields[0].split ("/")[1] : "apt";
                var new_version = fields[1];

                var old_version = "";
                var marker = trimmed.index_of ("upgradable from:");
                if (marker >= 0) {
                    old_version = trimmed.substring (marker + 16)
                        .replace ("]", "").strip ();
                }

                updates += PackageBackend.make_update (name, old_version, new_version, repo);
            }

            return updates;
        }

        public string[] refresh_argv () {
            return { "apt-get", "update" };
        }

        public string[] update_argv (string[] ids) {
            if (ids.length > 0) {
                string[] argv = { "apt-get", "install", "-y", "--only-upgrade" };
                foreach (var id in ids) {
                    argv += id;
                }
                return argv;
            }
            return { "apt-get", "dist-upgrade", "-y" };
        }
    }

    /** Fedora and RHEL: dnf check-update, upgraded with dnf upgrade. */
    public class DnfBackend : Object, PackageBackend {

        public string name { owned get { return "dnf"; } }

        public bool available () {
            return Environment.find_program_in_path ("dnf") != null;
        }

        public string[] list_argv () {
            return { "dnf", "--quiet", "check-update" };
        }

        public int[] list_success_codes () {
            // 100 means "updates are available" -- the normal case, not an error.
            return { 0, 100 };
        }

        public HashTable<string, Variant>[] parse_updates (string output) {
            HashTable<string, Variant>[] updates = {};

            foreach (var line in output.split ("\n")) {
                // "name.x86_64  1.2.4-1.fc40  updates"
                var trimmed = line.strip ();
                if (trimmed == "" || trimmed.has_prefix ("Last metadata")) {
                    continue;
                }

                var fields = split_whitespace (trimmed);
                if (fields.length < 3) {
                    continue;
                }

                var name = fields[0];
                var dot = name.last_index_of (".");
                if (dot > 0) {
                    name = name.substring (0, dot);  // strip the architecture
                }

                // dnf does not print the installed version here.
                updates += PackageBackend.make_update (name, "", fields[1], fields[2]);
            }

            return updates;
        }

        public string[] refresh_argv () {
            return { "dnf", "makecache" };
        }

        public string[] update_argv (string[] ids) {
            string[] argv = { "dnf", "upgrade", "-y" };
            foreach (var id in ids) {
                argv += id;
            }
            return argv;
        }

        internal static string[] split_whitespace (string line) {
            string[] fields = {};
            foreach (var part in line.split (" ")) {
                var trimmed = part.strip ();
                if (trimmed != "") {
                    fields += trimmed;
                }
            }
            return fields;
        }
    }

    /** openSUSE: zypper list-updates, upgraded with zypper update. */
    public class ZypperBackend : Object, PackageBackend {

        public string name { owned get { return "zypper"; } }

        public bool available () {
            return Environment.find_program_in_path ("zypper") != null;
        }

        public string[] list_argv () {
            return { "zypper", "--quiet", "--non-interactive", "--no-refresh",
                     "list-updates" };
        }

        public int[] list_success_codes () {
            return { 0, 100, 101, 102, 103 };
        }

        public HashTable<string, Variant>[] parse_updates (string output) {
            HashTable<string, Variant>[] updates = {};

            foreach (var line in output.split ("\n")) {
                // "v | repo | name | 1.2.3 | 1.2.4 | x86_64"
                if (!("|" in line)) {
                    continue;
                }

                var fields = line.split ("|");
                if (fields.length < 5) {
                    continue;
                }

                var status = fields[0].strip ();
                if (status != "v") {
                    continue;  // header and separator rows
                }

                updates += PackageBackend.make_update (
                    fields[2].strip (), fields[3].strip (),
                    fields[4].strip (), fields[1].strip ());
            }

            return updates;
        }

        public string[] refresh_argv () {
            return { "zypper", "--non-interactive", "refresh" };
        }

        public string[] update_argv (string[] ids) {
            string[] argv = { "zypper", "--non-interactive", "update" };
            foreach (var id in ids) {
                argv += id;
            }
            return argv;
        }
    }

    namespace PackageBackends {

        /**
         * Picks the backend for this machine.
         *
         * Selection is by what is installed rather than by what os-release
         * claims, because a container or a derivative can disagree with its own
         * ID. The distro family only breaks ties.
         */
        public PackageBackend? create () {
            PackageBackend[] candidates = {
                new PacmanBackend (),
                new AptBackend (),
                new DnfBackend (),
                new ZypperBackend (),
            };

            var family = Core.Distro.get_default ().family;
            var preferred = family_backend (family);

            foreach (var candidate in candidates) {
                if (candidate.name == preferred && candidate.available ()) {
                    return candidate;
                }
            }

            foreach (var candidate in candidates) {
                if (candidate.available ()) {
                    Core.Log.warn ("using %s though this looks like %s",
                                   candidate.name, family.to_string ());
                    return candidate;
                }
            }

            return null;
        }

        private string family_backend (Core.DistroFamily family) {
            switch (family) {
                case Core.DistroFamily.ARCH:   return "pacman";
                case Core.DistroFamily.DEBIAN: return "apt";
                case Core.DistroFamily.FEDORA: return "dnf";
                case Core.DistroFamily.SUSE:   return "zypper";
                default: return "";
            }
        }
    }
}
