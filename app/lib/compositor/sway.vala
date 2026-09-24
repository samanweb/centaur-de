namespace Centaur.Compositor {

    /**
     * sway, over its IPC socket.
     *
     * This is the only backend that can answer workspace and focus questions
     * today; see LabwcBackend for why labwc cannot yet.
     *
     * The wire format is i3's: the six bytes "i3-ipc", a 32-bit payload length
     * and a 32-bit message type, all in native byte order, followed by JSON.
     * Two connections are used -- one for request/reply, one held open for the
     * event stream -- because a reply and an event are indistinguishable on a
     * single socket.
     */
    public class SwayBackend : Object, Backend {

        private const string MAGIC = "i3-ipc";

        private enum MessageType {
            RUN_COMMAND = 0,
            GET_WORKSPACES = 1,
            SUBSCRIBE = 2,
            GET_TREE = 4,
        }

        // Event types arrive with the high bit set.
        private const uint32 EVENT_FLAG = 0x80000000u;

        private string socket_path;
        private SocketConnection? event_connection = null;
        private Workspace[] cached_workspaces = {};
        private Toplevel? cached_focus = null;

        public string name { owned get { return "sway"; } }

        public Capabilities capabilities {
            get {
                return Capabilities () {
                    workspaces = true,
                    focus_tracking = true,
                    window_placement = false,   // sway tiles; placement is not ours to set
                    titlebar_buttons = false,   // sway draws no titlebar buttons
                    animation_duration = false, // sway has no window animations
                };
            }
        }

        public SwayBackend (string socket_path) {
            this.socket_path = socket_path;
        }

        public async void start () throws GLib.Error {
            yield refresh_workspaces ();
            yield refresh_focus ();
            yield subscribe ();
        }

        public Workspace[] list_workspaces () {
            return cached_workspaces;
        }

        public Toplevel? focused_toplevel () {
            return cached_focus;
        }

        public async void switch_workspace (string id) throws GLib.Error {
            // The workspace name is user data. Quoting it keeps a workspace
            // called 'foo; exec rm' from becoming two sway commands.
            var command = "workspace \"%s\"".printf (id.replace ("\"", "\\\""));
            yield request (MessageType.RUN_COMMAND, command);
        }

        public async void apply_configuration () throws GLib.Error {
            // Nothing in org.centaur.compositor maps onto sway: it tiles, draws
            // no titlebar buttons and has no window animations. Reporting those
            // capabilities as false means the UI never offers them, so there is
            // nothing to apply. Deliberately a no-op, not an oversight.
        }

        private async void subscribe () throws GLib.Error {
            var client = new SocketClient ();
            event_connection = yield client.connect_async (
                new UnixSocketAddress (socket_path), null);

            yield write_message (event_connection.output_stream,
                                 MessageType.SUBSCRIBE,
                                 "[\"workspace\",\"window\"]");

            // Consume the subscription acknowledgement before the event loop.
            yield read_message (event_connection.input_stream, null);

            read_events.begin ();
        }

        private async void read_events () {
            while (event_connection != null) {
                try {
                    uint32 type;
                    var payload = yield read_message (event_connection.input_stream, out type);
                    if (payload == null) {
                        break;
                    }

                    var kind = type & ~EVENT_FLAG;
                    if (kind == 0) {          // workspace event
                        yield refresh_workspaces ();
                        workspaces_changed ();
                    } else if (kind == 3) {   // window event
                        yield refresh_focus ();
                        focus_changed ();
                    }
                } catch (GLib.Error e) {
                    Core.Log.warn ("sway event stream ended: %s", e.message);
                    break;
                }
            }
            event_connection = null;
        }

        private async void refresh_workspaces () throws GLib.Error {
            var payload = yield request (MessageType.GET_WORKSPACES, "");
            if (payload == null) {
                return;
            }

            var parser = new Json.Parser ();
            parser.load_from_data (payload);

            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                return;
            }

            Workspace[] found = {};
            root.get_array ().foreach_element ((array, index, element) => {
                if (element.get_node_type () != Json.NodeType.OBJECT) {
                    return;
                }
                var obj = element.get_object ();
                found += Workspace () {
                    id = obj.has_member ("name") ? obj.get_string_member ("name") : "",
                    name = obj.has_member ("name") ? obj.get_string_member ("name") : "",
                    active = obj.has_member ("focused") && obj.get_boolean_member ("focused"),
                    // sway does not report emptiness directly; a workspace with
                    // no representation in the tree simply is not listed, so
                    // anything we are told about is occupied or is the one we
                    // are looking at.
                    occupied = true,
                };
            });

            cached_workspaces = found;
        }

        private async void refresh_focus () throws GLib.Error {
            var payload = yield request (MessageType.GET_TREE, "");
            if (payload == null) {
                return;
            }

            var parser = new Json.Parser ();
            parser.load_from_data (payload);

            var root = parser.get_root ();
            cached_focus = (root != null && root.get_node_type () == Json.NodeType.OBJECT)
                ? find_focused (root.get_object ())
                : null;
        }

        /** Depth-first search for the node sway marks as focused. */
        private Toplevel? find_focused (Json.Object node) {
            if (node.has_member ("focused") && node.get_boolean_member ("focused")) {
                var type = node.has_member ("type") ? node.get_string_member ("type") : "";
                if (type == "con" || type == "floating_con") {
                    var app_id = (node.has_member ("app_id")
                                  && !node.get_null_member ("app_id"))
                        ? node.get_string_member ("app_id") : "";
                    var title = (node.has_member ("name")
                                 && !node.get_null_member ("name"))
                        ? node.get_string_member ("name") : "";
                    return new Toplevel (app_id, title);
                }
            }

            foreach (var key in new string[] { "nodes", "floating_nodes" }) {
                if (!node.has_member (key)) {
                    continue;
                }
                var children = node.get_array_member (key);
                for (uint i = 0; i < children.get_length (); i++) {
                    var child = children.get_element (i);
                    if (child.get_node_type () != Json.NodeType.OBJECT) {
                        continue;
                    }
                    var found = find_focused (child.get_object ());
                    if (found != null) {
                        return found;
                    }
                }
            }

            return null;
        }

        /** One request on its own connection, so replies never race events. */
        private async string? request (MessageType type, string payload) throws GLib.Error {
            var client = new SocketClient ();
            var connection = yield client.connect_async (
                new UnixSocketAddress (socket_path), null);

            yield write_message (connection.output_stream, type, payload);
            var reply = yield read_message (connection.input_stream, null);

            yield connection.close_async ();
            return reply;
        }

        private async void write_message (OutputStream stream,
                                          MessageType type,
                                          string payload) throws GLib.Error {
            var body = payload.data;
            var header = new uint8[14];

            Memory.copy (header, MAGIC.data, 6);
            write_u32 (header, 6, (uint32) body.length);
            write_u32 (header, 10, (uint32) type);

            yield stream.write_all_async (header, Priority.DEFAULT, null, null);
            if (body.length > 0) {
                yield stream.write_all_async (body, Priority.DEFAULT, null, null);
            }
        }

        private async string? read_message (InputStream stream,
                                            out uint32 type) throws GLib.Error {
            type = 0;

            var header = new uint8[14];
            size_t got;
            yield stream.read_all_async (header, Priority.DEFAULT, null, out got);
            if (got != header.length) {
                return null;
            }

            var length = read_u32 (header, 6);
            type = read_u32 (header, 10);

            if (length == 0) {
                return "";
            }
            // A malformed length must not turn into a huge allocation.
            if (length > 32 * 1024 * 1024) {
                throw new IOError.INVALID_DATA ("sway payload too large: %u", length);
            }

            // Room for a terminating NUL, because the result is read as a
            // string. The length is walked down and back up rather than sliced:
            // a Vala array slice assigned to a local is a copy, so reading into
            // one would fill the copy and leave this buffer zeroed.
            var body = new uint8[length + 1];
            body[length] = 0;
            body.length = (int) length;

            yield stream.read_all_async (body, Priority.DEFAULT, null, out got);

            body.length = (int) length + 1;

            if (got != length) {
                return null;
            }

            return (string) body;
        }

        // sway writes these fields in native byte order. Every architecture
        // Centaur targets is little-endian.
        private static void write_u32 (uint8[] buffer, int offset, uint32 value) {
            buffer[offset]     = (uint8) (value & 0xff);
            buffer[offset + 1] = (uint8) ((value >> 8) & 0xff);
            buffer[offset + 2] = (uint8) ((value >> 16) & 0xff);
            buffer[offset + 3] = (uint8) ((value >> 24) & 0xff);
        }

        private static uint32 read_u32 (uint8[] buffer, int offset) {
            return ((uint32) buffer[offset])
                 | ((uint32) buffer[offset + 1] << 8)
                 | ((uint32) buffer[offset + 2] << 16)
                 | ((uint32) buffer[offset + 3] << 24);
        }
    }
}
