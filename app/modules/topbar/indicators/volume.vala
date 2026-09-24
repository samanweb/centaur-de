namespace Centaur.Topbar {

    /**
     * Output volume.
     *
     * KNOWN SHORTCUT -- this drives pactl rather than talking to WirePlumber
     * directly. A native binding is the right answer and is Phase 2 work; a
     * long-lived `pactl subscribe` is event-driven rather than polled, so the
     * cost is one extra process and a parse, not a wakeup every second.
     */
    public class VolumeIndicator : TextIndicator, Indicator {

        private Subprocess? monitor = null;
        private bool muted = false;

        public string indicator_id { owned get { return "volume"; } }

        public VolumeIndicator () {
            add_css_class ("centaur-indicator");

            if (Environment.find_program_in_path ("pactl") == null) {
                Core.Log.debug ("pactl absent; volume indicator hidden");
                visible = false;
                return;
            }

            // Not a destructor: the watch() loop holds a reference to this
            // widget, so a destructor would never run and `pactl subscribe`
            // would outlive the bar. map/unmap is the hook that fires.
            map.connect (start_watching);
            unmap.connect (stop_watching);
        }

        private void start_watching () {
            if (monitor != null) {
                return;
            }
            refresh.begin ();
            watch.begin ();
        }

        private void stop_watching () {
            if (monitor == null) {
                return;
            }
            monitor.force_exit ();
            monitor = null;
        }

        /** Follows PipeWire's event stream; re-reads only when something moves. */
        private async void watch () {
            try {
                monitor = new Subprocess.newv (
                    { "pactl", "subscribe" },
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
            } catch (GLib.Error e) {
                Core.Log.warn ("cannot watch audio events: %s", e.message);
                return;
            }

            var watched = monitor;
            var stream = new DataInputStream (watched.get_stdout_pipe ());

            while (true) {
                string? line;
                try {
                    line = yield stream.read_line_async ();
                } catch (GLib.Error e) {
                    break;
                }
                if (line == null) {
                    break;
                }
                // stop_watching() swaps the field out from under us; anything
                // read after that belongs to a subscription we have abandoned.
                if (monitor != watched) {
                    break;
                }
                if ("sink" in line) {
                    yield refresh ();
                }
            }
        }

        private async void refresh () {
            var volume = yield read_command (
                { "pactl", "get-sink-volume", "@DEFAULT_SINK@" });
            var mute = yield read_command (
                { "pactl", "get-sink-mute", "@DEFAULT_SINK@" });

            muted = (mute != null && "yes" in mute);

            var percent = parse_percent (volume);
            if (percent < 0) {
                visible = false;
                return;
            }

            visible = true;
            label = muted ? "muted" : @"$percent%";
            tooltip_text = muted ? "Output muted" : @"Output volume $percent%";
        }

        /**
         * pactl prints one channel per line:
         *   Volume: front-left: 42663 /  65% / -11.00 dB, front-right: ...
         * The first percentage is taken; channels are locked together in every
         * configuration Centaur exposes.
         */
        private static int parse_percent (string? output) {
            if (output == null) {
                return -1;
            }

            var index = output.index_of ("%");
            if (index < 0) {
                return -1;
            }

            var start = index;
            while (start > 0 && output[start - 1].isdigit ()) {
                start--;
            }
            if (start == index) {
                return -1;
            }

            return int.parse (output.substring (start, index - start));
        }

        private static async string? read_command (string[] argv) {
            try {
                var process = new Subprocess.newv (argv,
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
                string output;
                yield process.communicate_utf8_async (null, null, out output, null);
                return output;
            } catch (GLib.Error e) {
                return null;
            }
        }
    }
}
