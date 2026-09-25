namespace Centaur.Settingsd {

    // Held for the life of the process: the output manager calls back into it.
    private static DisplayApplier? displays = null;

    public static int main (string[] args) {
        Environment.set_prgname ("centaur-settingsd");

        var loop = new MainLoop ();
        var backend = Compositor.Detect.create ();

        backend.start.begin ((source, result) => {
            try {
                backend.start.end (result);
            } catch (GLib.Error e) {
                Core.Log.warn ("compositor backend did not start: %s", e.message);
            }

            var applier = new Applier (backend);
            applier.apply_all ();

            displays = new DisplayApplier ();
            displays.start ();

            Core.Log.info ("centaur-settingsd %s ready (compositor: %s)",
                           Version.STRING, backend.name);
        });

        Unix.signal_add ((int) Posix.Signal.TERM, () => { loop.quit (); return Source.REMOVE; });
        Unix.signal_add ((int) Posix.Signal.INT,  () => { loop.quit (); return Source.REMOVE; });

        loop.run ();
        return 0;
    }
}
