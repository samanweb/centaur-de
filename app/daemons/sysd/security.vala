namespace Centaur.Sysd {

    /**
     * Disk encryption and boot security status for the Security page.
     *
     * Everything reported here is a fact about the machine, not an opinion
     * about it. The page renders the judgement; the daemon does not, because a
     * daemon that decided "your system is insecure" would be making a policy
     * call that belongs to the user.
     */
    [DBus (name = "org.centaur.System1.Security")]
    public class SecurityService : Object {

        private Polkit polkit;

        public SecurityService (Polkit polkit) {
            this.polkit = polkit;
        }

        public async HashTable<string, Variant> get_status (
                GLib.BusName sender) throws GLib.Error {
            yield polkit.require (sender, "org.centaur.system1.security.read");

            var status = new HashTable<string, Variant> (str_hash, str_equal);

            var efi = FileUtils.test ("/sys/firmware/efi", FileTest.IS_DIR);
            status.insert ("efi", new Variant.boolean (efi));
            status.insert ("secure-boot", new Variant.string (secure_boot_state (efi)));

            status.insert ("tpm", new Variant.boolean (
                FileUtils.test ("/sys/class/tpm/tpm0", FileTest.EXISTS)));

            var encrypted = yield has_luks ();
            status.insert ("disk-encryption", new Variant.string (
                encrypted ? "luks" : "none"));

            status.insert ("firewall", new Variant.string (firewall_backend ()));

            return status;
        }

        /**
         * Reads the EFI SecureBoot variable.
         *
         * The variable's first four bytes are an attribute mask; the fifth is
         * the flag. Returns "unknown" rather than guessing when it cannot be
         * read -- claiming Secure Boot is off when it is merely unreadable
         * would be a lie in the more alarming direction.
         */
        private static string secure_boot_state (bool efi) {
            if (!efi) {
                return "not-applicable";
            }

            var dir = "/sys/firmware/efi/efivars";
            if (!FileUtils.test (dir, FileTest.IS_DIR)) {
                return "unknown";
            }

            try {
                var directory = Dir.open (dir);
                string? entry;
                while ((entry = directory.read_name ()) != null) {
                    if (!entry.has_prefix ("SecureBoot-")) {
                        continue;
                    }

                    uint8[] contents;
                    var file = File.new_for_path (Path.build_filename (dir, entry));
                    file.load_contents (null, out contents, null);

                    if (contents.length >= 5) {
                        return contents[4] == 1 ? "enabled" : "disabled";
                    }
                }
            } catch (GLib.Error e) {
                Core.Log.debug ("secure boot state unreadable: %s", e.message);
            }

            return "unknown";
        }

        private static async bool has_luks () {
            try {
                var output = yield PackagesService.run_capture (
                    { "lsblk", "--noheadings", "--output", "TYPE" }, { 0 });

                foreach (var line in output.split ("\n")) {
                    if (line.strip () == "crypt") {
                        return true;
                    }
                }
            } catch (GLib.Error e) {
                Core.Log.debug ("cannot determine encryption state: %s", e.message);
            }
            return false;
        }

        private static string firewall_backend () {
            if (Environment.find_program_in_path ("firewall-cmd") != null) {
                return "firewalld";
            }
            if (Environment.find_program_in_path ("ufw") != null) {
                return "ufw";
            }
            if (Environment.find_program_in_path ("nft") != null) {
                return "nftables";
            }
            return "none";
        }
    }
}
