namespace Centaur.Topbar {

    /**
     * Shared state handed to every indicator.
     *
     * One compositor backend is created for the process and passed around,
     * rather than each indicator connecting for itself.
     */
    public class Context : Object {
        public Compositor.Backend compositor { get; construct; }
        public Core.Config config { get; construct; }

        public Context (Compositor.Backend compositor) {
            Object (compositor: compositor, config: Core.Config.get_default ());
        }
    }

    /**
     * One item in the bar.
     *
     * Indicators are compiled in rather than loaded as plugins: the layout is
     * data-driven through GSettings, but the code is not pluggable. That buys
     * reorderability without an ABI to maintain.
     *
     * Every indicator subscribes to its source. None polls. The clock is the
     * only timer in the bar, and it wakes on the minute boundary.
     */
    public interface Indicator : Gtk.Widget {
        public abstract string indicator_id { owned get; }
    }

    /**
     * Base for an indicator that is a single piece of text.
     *
     * GtkLabel is final in GTK4, so a text indicator wraps a label instead of
     * being one. `label` forwards to that caption, and the css classes stay on
     * the indicator itself, where font and colour inherit down to the caption.
     */
    public abstract class TextIndicator : Gtk.Box {

        protected Gtk.Label caption;

        public string label {
            get { return caption.label; }
            set { caption.label = value; }
        }

        construct {
            caption = new Gtk.Label ("");
            append (caption);
        }
    }

    namespace Indicators {

        /**
         * Builds an indicator by id, or null if this session cannot support it.
         *
         * Returning null is how the Capabilities mechanism reaches the bar: on
         * labwc there is no workspace or focus information to be had, so those
         * two indicators are absent rather than empty or wrong.
         */
        public Indicator? create (string id, Context context) {
            switch (id) {
                case "launcher":
                    return new LauncherIndicator ();

                case "workspaces":
                    if (!context.compositor.capabilities.workspaces) {
                        Core.Log.debug ("%s cannot report workspaces; indicator omitted",
                                        context.compositor.name);
                        return null;
                    }
                    return new WorkspacesIndicator (context);

                case "focused-window":
                    if (!context.compositor.capabilities.focus_tracking) {
                        Core.Log.debug ("%s cannot report focus; indicator omitted",
                                        context.compositor.name);
                        return null;
                    }
                    return new FocusedWindowIndicator (context);

                case "network": return new NetworkIndicator ();
                case "volume":  return new VolumeIndicator ();
                case "battery": return new BatteryIndicator ();
                case "clock":   return new ClockIndicator (context);
                case "power":   return new PowerIndicator ();

                default:
                    Core.Log.warn ("unknown indicator id '%s' in topbar layout", id);
                    return null;
            }
        }
    }
}
