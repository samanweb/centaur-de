[CCode (cheader_filename = "output-manager.h")]
namespace Centaur.Native {

    [CCode (cname = "CentaurOutputChangedFunc", has_target = true)]
    public delegate void OutputChangedFunc (GLib.Variant heads);

    [CCode (cname = "CentaurOutputResultFunc", has_target = true)]
    public delegate void OutputResultFunc (string result);

    [Compact]
    [CCode (cname = "CentaurOutputManager", free_function = "centaur_output_manager_free")]
    public class OutputManager {
        [CCode (cname = "centaur_output_manager_new_for_display")]
        public static OutputManager? for_display (void* wl_display, OutputChangedFunc changed);

        [CCode (cname = "centaur_output_manager_new_connected")]
        public static OutputManager? connected (OutputChangedFunc changed);

        [CCode (cname = "centaur_output_manager_is_ready")]
        public bool is_ready ();

        [CCode (cname = "centaur_output_manager_apply")]
        public void apply (GLib.Variant config, bool test, owned OutputResultFunc result);
    }
}
