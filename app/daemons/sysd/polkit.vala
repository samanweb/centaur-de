namespace Centaur.Sysd {

    /**
     * polkit authorisation for every method that changes state.
     *
     * The call is built as raw Variants rather than through a generated proxy:
     * CheckAuthorization takes a nested struct, and hand-marshalling it is less
     * fragile than teaching Vala the shape of polkit's subject type.
     *
     * Every mutating method calls this before touching the system. A method
     * that forgets to is a security bug, and the contract test in
     * tests/ exists to catch exactly that.
     */
    public class Polkit : Object {

        private const string AUTHORITY_NAME = "org.freedesktop.PolicyKit1";
        private const string AUTHORITY_PATH = "/org/freedesktop/PolicyKit1/Authority";
        private const string AUTHORITY_IFACE = "org.freedesktop.PolicyKit1.Authority";

        // AllowUserInteraction: polkit may show the agent's prompt.
        private const uint32 ALLOW_INTERACTION = 1;

        private DBusConnection connection;

        public Polkit (DBusConnection connection) {
            this.connection = connection;
        }

        /**
         * Throws SystemError.UNAUTHORIZED unless the caller may perform action.
         *
         * Throwing rather than returning a boolean is deliberate: a caller that
         * ignores a returned false still runs the privileged code, whereas an
         * ignored exception cannot.
         */
        public async void require (string sender, string action) throws GLib.Error {
            var subject_details = new VariantBuilder (new VariantType ("a{sv}"));
            subject_details.add ("{sv}", "name", new Variant.string (sender));

            var subject = new Variant.tuple ({
                new Variant.string ("system-bus-name"),
                subject_details.end (),
            });

            var details = new VariantBuilder (new VariantType ("a{ss}"));

            var parameters = new Variant.tuple ({
                subject,
                new Variant.string (action),
                details.end (),
                new Variant.uint32 (ALLOW_INTERACTION),
                new Variant.string (""),
            });

            Variant reply;
            try {
                reply = yield connection.call (
                    AUTHORITY_NAME, AUTHORITY_PATH, AUTHORITY_IFACE,
                    "CheckAuthorization", parameters,
                    new VariantType ("((bba{ss}))"),
                    DBusCallFlags.NONE, -1, null);
            } catch (GLib.Error e) {
                // No polkit means we cannot establish that the caller is
                // allowed, so the answer is no. Failing open here would make
                // every mutating method world-callable.
                Core.Log.error ("polkit unreachable, denying %s: %s", action, e.message);
                throw new Core.SystemError.UNAUTHORIZED (
                    "authorisation service unavailable");
            }

            var result = reply.get_child_value (0);
            var authorised = result.get_child_value (0).get_boolean ();

            if (!authorised) {
                Core.Log.info ("denied %s to %s", action, sender);
                throw new Core.SystemError.UNAUTHORIZED (
                    "not authorised for %s".printf (action));
            }
        }
    }
}
