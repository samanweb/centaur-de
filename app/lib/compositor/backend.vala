namespace Centaur.Compositor {

    public struct Workspace {
        string id;
        string name;
        bool active;
        bool occupied;
    }

    /**
     * The focused window, as much of it as the shell needs.
     *
     * A class rather than a struct because it is returned nullable across an
     * interface boundary, and nullable structs are the kind of Vala corner that
     * works until it does not.
     */
    public class Toplevel : Object {
        public string app_id { get; construct; }
        public string title { get; construct; }

        public Toplevel (string app_id, string title) {
            Object (app_id: app_id, title: title);
        }
    }

    /**
     * What the running compositor can actually do.
     *
     * labwc and sway do not support the same set. Rather than write a setting
     * that silently does nothing, the UI reads this and disables the controls
     * the running compositor cannot honour. This is the mechanism
     * architecture.md section 5 describes, and it is why every backend must be
     * honest about its gaps rather than pretend.
     */
    public struct Capabilities {
        bool workspaces;
        bool focus_tracking;
        bool window_placement;
        bool titlebar_buttons;
        bool animation_duration;
    }

    /**
     * One compositor, seen from the shell.
     *
     * Centaur does not composite. This is a configuration and introspection
     * adapter over a compositor someone else wrote.
     */
    public interface Backend : Object {

        public abstract string name { owned get; }
        public abstract Capabilities capabilities { get; }

        /** Connects and begins whatever subscription the backend supports. */
        public abstract async void start () throws GLib.Error;

        public abstract Workspace[] list_workspaces ();
        public abstract async void switch_workspace (string id) throws GLib.Error;
        public abstract Toplevel? focused_toplevel ();

        /**
         * Writes the current org.centaur.compositor settings out to the
         * compositor and asks it to reload.
         */
        public abstract async void apply_configuration () throws GLib.Error;

        public signal void workspaces_changed ();
        public signal void focus_changed ();
    }
}
