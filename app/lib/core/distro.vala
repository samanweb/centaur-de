namespace Centaur.Core {

    /**
     * Which family of distribution we are running on.
     *
     * Centaur supports four. Nothing above centaur-sysd is allowed to branch on
     * this: the UI never learns a distro name. It exists so the daemon can pick
     * a backend, and so the About card can print something truthful.
     */
    public enum DistroFamily {
        ARCH,
        DEBIAN,
        FEDORA,
        SUSE,
        UNKNOWN;

        public string to_string () {
            switch (this) {
                case ARCH:   return "arch";
                case DEBIAN: return "debian";
                case FEDORA: return "fedora";
                case SUSE:   return "suse";
                default:     return "unknown";
            }
        }
    }

    /**
     * Reads /etc/os-release once and answers questions about it.
     */
    public class Distro : Object {

        private static Distro? instance = null;

        public string id { get; private set; default = "unknown"; }
        public string name { get; private set; default = "Unknown"; }
        public string version { get; private set; default = ""; }
        public DistroFamily family { get; private set; default = DistroFamily.UNKNOWN; }

        public static unowned Distro get_default () {
            if (instance == null) {
                instance = new Distro ();
            }
            return instance;
        }

        private Distro () {
            var fields = read_os_release ();

            if (fields.contains ("ID")) {
                this.id = fields.lookup ("ID");
            }
            if (fields.contains ("PRETTY_NAME")) {
                this.name = fields.lookup ("PRETTY_NAME");
            } else if (fields.contains ("NAME")) {
                this.name = fields.lookup ("NAME");
            }
            if (fields.contains ("VERSION_ID")) {
                this.version = fields.lookup ("VERSION_ID");
            }

            // ID_LIKE matters more than ID: Manjaro is arch-like, Linux Mint is
            // debian-like, and neither says so in ID.
            var like = fields.contains ("ID_LIKE") ? fields.lookup ("ID_LIKE") : "";
            this.family = classify (this.id, like);

            Log.debug ("distro: id=%s family=%s (%s)",
                       this.id, this.family.to_string (), this.name);
        }

        private static DistroFamily classify (string id, string id_like) {
            var haystack = @"$id $id_like".down ();

            // Order matters where a distro claims several ancestries.
            if ("arch" in haystack)     return DistroFamily.ARCH;
            if ("debian" in haystack)   return DistroFamily.DEBIAN;
            if ("ubuntu" in haystack)   return DistroFamily.DEBIAN;
            if ("fedora" in haystack)   return DistroFamily.FEDORA;
            if ("rhel" in haystack)     return DistroFamily.FEDORA;
            if ("suse" in haystack)     return DistroFamily.SUSE;
            if ("opensuse" in haystack) return DistroFamily.SUSE;

            return DistroFamily.UNKNOWN;
        }

        private static HashTable<string, string> read_os_release () {
            var fields = new HashTable<string, string> (str_hash, str_equal);

            // /usr/lib is the fallback the spec defines for stateless systems.
            foreach (var path in new string[] { "/etc/os-release", "/usr/lib/os-release" }) {
                string contents;
                try {
                    if (!FileUtils.test (path, FileTest.EXISTS)) {
                        continue;
                    }
                    FileUtils.get_contents (path, out contents);
                } catch (FileError e) {
                    Log.warn ("cannot read %s: %s", path, e.message);
                    continue;
                }

                foreach (var line in contents.split ("\n")) {
                    var trimmed = line.strip ();
                    if (trimmed == "" || trimmed.has_prefix ("#")) {
                        continue;
                    }
                    var split = trimmed.split ("=", 2);
                    if (split.length != 2) {
                        continue;
                    }
                    var value = split[1].strip ();
                    // Values may be quoted with either quote character.
                    if (value.length >= 2 &&
                        ((value.has_prefix ("\"") && value.has_suffix ("\"")) ||
                         (value.has_prefix ("'") && value.has_suffix ("'")))) {
                        value = value.substring (1, value.length - 2);
                    }
                    fields.insert (split[0].strip (), value);
                }
                break;
            }

            return fields;
        }
    }
}
