namespace Centaur.Displays {

    /**
     * The display layout the user chose to keep, in
     * $XDG_CONFIG_HOME/centaur/displays.json.
     *
     * wlr-output-management changes only the running session; the compositor
     * forgets them at logout. centaur-displays writes this file when the user
     * keeps a change, and centaur-settingsd reads it back at login and on
     * hotplug.
     *
     * One entry per monitor, keyed by Head.identity, so a monitor keeps its
     * settings whichever port it is plugged into and whatever else is
     * connected. Modes are stored by size and refresh, never by index:
     * indices are only meaningful within one snapshot.
     */
    public class Store : Object {

        public static string path () {
            return Path.build_filename (Environment.get_user_config_dir (),
                                        "centaur", "displays.json");
        }

        public void save (Head[] heads) throws GLib.Error {
            // Merge rather than replace: a monitor unplugged right now keeps
            // what it had.
            var root = read () ?? new Json.Object ();
            var outputs = root.has_member ("outputs")
                ? root.get_object_member ("outputs")
                : new Json.Object ();

            foreach (var head in heads) {
                var entry = new Json.Object ();
                entry.set_boolean_member ("enabled", head.enabled);
                var mode = head.effective_mode ();
                if (mode != null) {
                    entry.set_int_member ("width", mode.width);
                    entry.set_int_member ("height", mode.height);
                    entry.set_int_member ("refresh", mode.refresh);
                }
                entry.set_int_member ("x", head.x);
                entry.set_int_member ("y", head.y);
                entry.set_int_member ("transform", head.transform);
                entry.set_double_member ("scale", head.scale);
                entry.set_string_member ("name", head.name);   // for a reader, not for matching
                outputs.set_object_member (head.identity, entry);
            }

            root.set_int_member ("version", 1);
            root.set_object_member ("outputs", outputs);

            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (root);
            var generator = new Json.Generator () { root = node, pretty = true };

            DirUtils.create_with_parents (Path.get_dirname (path ()), 0700);
            // Written whole, then renamed: a half-written file read at login
            // would lose every monitor's settings, not just the one changed.
            FileUtils.set_contents (path (), generator.to_data (null));
        }

        /**
         * Overwrites each head with its saved settings, where it has any.
         * Returns whether anything changed. A saved mode the monitor no longer
         * offers is skipped rather than guessed at.
         */
        public bool restore (Head[] heads) {
            var root = read ();
            if (root == null || !root.has_member ("outputs")) {
                return false;
            }
            var outputs = root.get_object_member ("outputs");

            var changed = false;
            foreach (var head in heads) {
                if (!outputs.has_member (head.identity)) {
                    continue;
                }
                var entry = outputs.get_object_member (head.identity);
                var before = head.copy ();

                head.enabled = entry.get_boolean_member_with_default ("enabled", true);
                if (head.enabled) {
                    var index = head.find_mode (
                        (int) entry.get_int_member_with_default ("width", 0),
                        (int) entry.get_int_member_with_default ("height", 0),
                        (int) entry.get_int_member_with_default ("refresh", 0));
                    if (index >= 0) {
                        head.current = index;
                    } else if (head.current < 0) {
                        head.current = head.preferred_index ();
                    }
                    head.x = (int) entry.get_int_member_with_default ("x", head.x);
                    head.y = (int) entry.get_int_member_with_default ("y", head.y);
                    head.transform = (int) entry.get_int_member_with_default ("transform", 0);
                    head.scale = entry.get_double_member_with_default ("scale", 1.0);
                }

                if (!head.same_state (before)) {
                    changed = true;
                }
            }

            // Never leave the user with every display switched off.
            var any_enabled = false;
            foreach (var head in heads) {
                any_enabled |= head.enabled;
            }
            if (!any_enabled && heads.length > 0) {
                heads[0].enabled = true;
                if (heads[0].current < 0) {
                    heads[0].current = heads[0].preferred_index ();
                }
            }

            return changed;
        }

        private Json.Object? read () {
            if (!FileUtils.test (path (), FileTest.EXISTS)) {
                return null;
            }
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (path ());
                var root = parser.get_root ();
                return root != null && root.get_node_type () == Json.NodeType.OBJECT
                    ? root.get_object ()
                    : null;
            } catch (GLib.Error e) {
                Core.Log.warn ("ignoring unreadable %s: %s", path (), e.message);
                return null;
            }
        }
    }
}
