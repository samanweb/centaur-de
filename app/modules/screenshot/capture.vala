namespace Centaur.Screenshot {

    public enum Mode {
        /** Every display, as one image. */
        SCREEN,
        /** One display, picked by clicking it. */
        DISPLAY,
        /** A rectangle dragged out with the pointer. */
        AREA;

        public static Mode? parse (string value) {
            switch (value) {
                case "screen":  return SCREEN;
                case "display": return DISPLAY;
                case "area":    return AREA;
                default:        return null;
            }
        }
    }

    public errordomain CaptureError {
        /** The user pressed Escape while choosing: not an error to report. */
        CANCELLED,
        MISSING_TOOL,
        FAILED,
    }

    /**
     * Takes a screenshot with grim, choosing the region with slurp.
     *
     * Both speak the wlroots capture protocols labwc implements
     * (wlr-screencopy, ext-image-copy-capture), and both are a few dozen
     * kilobytes: the same split of work as swaybg for the wallpaper, where
     * Centaur owns the experience and a small standard tool does the pixels.
     */
    namespace Capture {

        public static async string take (Mode mode) throws GLib.Error {
            require ("grim");

            string[] grim = { "grim" };
            if (mode != Mode.SCREEN) {
                require ("slurp");
                grim += "-g";
                grim += yield select_region (mode);
            }

            var path = target_path ();
            grim += path;

            string ignored, errors;
            var captured = yield run (grim, out ignored, out errors);
            if (!captured) {
                throw new CaptureError.FAILED ("grim could not capture the screen: %s",
                                               errors.strip ());
            }

            // The file is the screenshot; the clipboard is a convenience, so
            // failing to fill it is logged rather than reported as a failure.
            yield copy_to_clipboard (path);
            return path;
        }

        /**
         * Runs slurp and returns its "x,y wxh" geometry. slurp exits non-zero
         * when the user presses Escape, which is a cancellation.
         */
        private static async string select_region (Mode mode) throws GLib.Error {
            var accent = Ui.Theme.accent_hex ("dark").replace ("#", "");
            string[] argv = {
                "slurp",
                "-d",                         // show the size while dragging
                "-b", "00000066",             // dim what is not selected
                "-c", accent + "ff",          // outline in the accent colour
                "-s", accent + "22",          // faint accent fill inside
                "-w", "2",
                "-F", "Inter",
            };
            if (mode == Mode.DISPLAY) {
                argv += "-o";                 // pick a whole output
            }

            string output, ignored;
            var selected = yield run (argv, out output, out ignored);
            if (!selected || output.strip () == "") {
                throw new CaptureError.CANCELLED ("selection cancelled");
            }
            return output.strip ();
        }

        /**
         * wl-copy keeps a small process alive holding the image, because on
         * Wayland a clipboard dies with the program that set it -- and this
         * one exits right after the screenshot.
         */
        private static async void copy_to_clipboard (string path) {
            if (Environment.find_program_in_path ("wl-copy") == null) {
                Core.Log.warn ("wl-copy is not installed; screenshot not copied");
                return;
            }
            try {
                var launcher = new SubprocessLauncher (SubprocessFlags.STDERR_SILENCE);
                launcher.set_stdin_file_path (path);
                var process = launcher.spawnv ({ "wl-copy", "--type", "image/png" });
                yield process.wait_async ();
            } catch (GLib.Error e) {
                Core.Log.warn ("cannot copy the screenshot: %s", e.message);
            }
        }

        /** ~/Pictures/Screenshots/Screenshot from 2026-09-25 10-15-30.png */
        public static string target_path () {
            var dir = Path.build_filename (pictures_dir (), "Screenshots");
            DirUtils.create_with_parents (dir, 0755);

            var stamp = new DateTime.now_local ().format ("%Y-%m-%d %H-%M-%S");
            var path = Path.build_filename (dir, @"Screenshot from $stamp.png");
            // Two in the same second get a suffix rather than overwriting.
            for (var i = 2; FileUtils.test (path, FileTest.EXISTS); i++) {
                path = Path.build_filename (dir, @"Screenshot from $stamp ($i).png");
            }
            return path;
        }

        public static string pictures_dir () {
            var pictures = Environment.get_user_special_dir (UserDirectory.PICTURES);
            if (pictures == null || pictures == Environment.get_home_dir ()) {
                pictures = Path.build_filename (Environment.get_home_dir (), "Pictures");
            }
            return pictures;
        }

        private static void require (string program) throws CaptureError {
            if (Environment.find_program_in_path (program) == null) {
                throw new CaptureError.MISSING_TOOL (
                    "%s is not installed.\nInstall it with: sudo pacman -S %s", program, program);
            }
        }

        private static async bool run (string[] argv, out string stdout_text,
                                       out string stderr_text) throws GLib.Error {
            var process = new Subprocess.newv (
                argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            string? out_text, err_text;
            yield process.communicate_utf8_async (null, null, out out_text, out err_text);
            stdout_text = out_text ?? "";
            stderr_text = err_text ?? "";
            return process.get_successful ();
        }
    }
}
