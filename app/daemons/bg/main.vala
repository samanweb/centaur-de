namespace Centaur.Bg {

    [CCode (cheader_filename = "sys/prctl.h", cname = "prctl")]
    private extern int prctl (int option, ulong arg2, ulong arg3 = 0, ulong arg4 = 0, ulong arg5 = 0);
    private const int PR_SET_PDEATHSIG = 1;

    /**
     * centaur-bg: the desktop wallpaper.
     *
     * Drawing is swaybg's job. It is a few dozen kilobytes, speaks
     * wlr-layer-shell on the background layer, follows outputs as they come
     * and go, and scales per output -- everything a wallpaper needs and
     * nothing more. This process owns *which* wallpaper: it turns
     * org.centaur.appearance into a swaybg command line and keeps exactly one
     * swaybg running for it.
     *
     * This settles architecture.md's open question about centaur-bg: it stays
     * a separate process, and settingsd stays free of process supervision
     * for a renderer it does not own.
     */
    public class Painter : Object {

        // swaybg has no "drawn" signal. It maps within a frame or two; the
        // old one is kept this long so a change never flashes the bare
        // compositor background.
        private const uint HANDOVER_MS = 500;

        private const int MAX_CRASHES = 3;
        private const int CRASH_WINDOW_SECONDS = 60;

        private Settings settings;
        private Subprocess? current = null;
        private uint queued = 0;
        private bool stopping = false;
        private int crashes = 0;
        private int64 crash_window = 0;
        private bool warned_missing = false;

        public Painter () {
            settings = Core.Config.get_default ().appearance;
            foreach (var key in new string[] { "wallpaper", "wallpaper-mode", "background-color" }) {
                settings.changed[key].connect (() => queue_repaint ());
            }
        }

        public void start () {
            paint ();
        }

        public void stop () {
            stopping = true;
            if (current != null) {
                current.send_signal ((int) Posix.Signal.TERM);
                current = null;
            }
        }

        /** Coalesces a burst of key changes -- picking a file sets two. */
        private void queue_repaint () {
            if (queued != 0) {
                Source.remove (queued);
            }
            queued = Timeout.add (50, () => {
                queued = 0;
                crashes = 0;   // a deliberate change deserves a fresh start
                paint ();
                return Source.REMOVE;
            });
        }

        public string[]? command () {
            var mode = settings.get_string ("wallpaper-mode");
            var color = normalize_color (settings.get_string ("background-color"));

            if (mode != "solid") {
                var image = Core.Wallpaper.resolve (settings.get_string ("wallpaper"));
                if (image != null) {
                    return { "swaybg", "--image", image, "--mode", mode, "--color", color };
                }
            }
            return { "swaybg", "--color", color, "--mode", "solid_color" };
        }

        /** swaybg takes #rrggbb; anything else falls back to the palette's window colour. */
        private static string normalize_color (string value) {
            var color = value.strip ();
            if (!color.has_prefix ("#")) {
                color = "#" + color;
            }
            if (color.length != 7) {
                return "#0b0f14";
            }
            for (var i = 1; i < 7; i++) {
                if (!color[i].isxdigit ()) {
                    return "#0b0f14";
                }
            }
            return color;
        }

        private void paint () {
            if (stopping) {
                return;
            }
            if (Environment.find_program_in_path ("swaybg") == null) {
                if (!warned_missing) {
                    Core.Log.error ("swaybg is not installed; no wallpaper will be drawn");
                    warned_missing = true;
                }
                return;
            }

            var argv = command ();
            Subprocess next;
            try {
                var launcher = new SubprocessLauncher (SubprocessFlags.NONE);
                // Dies with us: a crashed centaur-bg must not leave an orphan
                // swaybg stacked under the next one.
                launcher.set_child_setup (() => {
                    prctl (PR_SET_PDEATHSIG, (ulong) Posix.Signal.TERM);
                });
                next = launcher.spawnv (argv);
            } catch (GLib.Error e) {
                Core.Log.error ("cannot start swaybg: %s", e.message);
                return;
            }
            Core.Log.info ("wallpaper: %s", string.joinv (" ", argv));

            var previous = current;
            current = next;
            watch.begin (next);

            if (previous != null) {
                Timeout.add (HANDOVER_MS, () => {
                    previous.send_signal ((int) Posix.Signal.TERM);
                    return Source.REMOVE;
                });
            }
        }

        /** Respawns a swaybg that died on its own, with a cap like the session's. */
        private async void watch (Subprocess process) {
            try {
                yield process.wait_async (null);
            } catch (GLib.Error e) {
                return;
            }
            if (stopping || process != current) {
                return;   // replaced or stopped on purpose
            }

            current = null;
            var now = get_monotonic_time () / 1000000;
            if (now - crash_window > CRASH_WINDOW_SECONDS) {
                crash_window = now;
                crashes = 0;
            }
            crashes++;
            if (crashes > MAX_CRASHES) {
                Core.Log.error ("swaybg exited %d times in %d s; leaving the wallpaper off",
                                crashes, CRASH_WINDOW_SECONDS);
                return;
            }
            var delay = 1u << (crashes - 1);
            Core.Log.warn ("swaybg exited; restarting in %us", delay);
            Timeout.add_seconds (delay, () => {
                paint ();
                return Source.REMOVE;
            });
        }
    }

    public static int main (string[] args) {
        Environment.set_prgname ("centaur-bg");

        if (Environment.get_variable ("WAYLAND_DISPLAY") == null) {
            printerr ("centaur-bg: no WAYLAND_DISPLAY; this is started inside the session\n");
            return 1;
        }

        var loop = new MainLoop ();
        var painter = new Painter ();
        painter.start ();

        Unix.signal_add ((int) Posix.Signal.TERM, () => {
            painter.stop ();
            loop.quit ();
            return Source.REMOVE;
        });
        Unix.signal_add ((int) Posix.Signal.INT, () => {
            painter.stop ();
            loop.quit ();
            return Source.REMOVE;
        });

        loop.run ();
        return 0;
    }
}
