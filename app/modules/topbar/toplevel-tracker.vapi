[CCode (cheader_filename = "toplevel-tracker.h")]
namespace Centaur.Native {

    [CCode (cname = "CentaurToplevelEvent", cprefix = "CENTAUR_TOPLEVEL_", has_type_id = false)]
    public enum ToplevelEvent {
        CHANGED,
        CLOSED,
    }

    [CCode (cname = "CentaurToplevelFunc", has_target = true)]
    public delegate void ToplevelFunc (ToplevelEvent event, uint id, string app_id,
                                       string title, bool activated, bool minimized);

    [Compact]
    [CCode (cname = "CentaurToplevelTracker", free_function = "centaur_toplevel_tracker_free")]
    public class ToplevelTracker {
        [CCode (cname = "centaur_toplevel_tracker_new")]
        public static ToplevelTracker? create (Gdk.Display display, ToplevelFunc func);

        [CCode (cname = "centaur_toplevel_tracker_activate")]
        public void activate (uint id);

        [CCode (cname = "centaur_toplevel_tracker_minimize")]
        public void minimize (uint id);
    }
}
