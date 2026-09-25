namespace Centaur.Core.Wallpaper {

    /** The one shipped wallpaper that stands for "nothing chosen". */
    public const string DEFAULT_NAME = "centaur-emerald-dark.svg";

    /** Formats gdk-pixbuf reads in any standard install, so swaybg can too. */
    private const string[] EXTENSIONS = { ".jpg", ".jpeg", ".png", ".webp", ".svg", ".bmp" };

    public static bool is_image (string path) {
        var lower = path.down ();
        foreach (var extension in EXTENSIONS) {
            if (lower.has_suffix (extension)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Where Centaur's own wallpapers are installed.
     *
     * CENTAUR_THEME_DIR's sibling first, so an uninstalled tree finds the
     * generated app/data/backgrounds, then the XDG data directories.
     */
    public static string? centaur_dir () {
        var theme = Environment.get_variable ("CENTAUR_THEME_DIR");
        if (theme != null) {
            var sibling = Path.build_filename (Path.get_dirname (theme), "backgrounds");
            if (FileUtils.test (sibling, FileTest.IS_DIR)) {
                return sibling;
            }
        }
        foreach (var data_dir in Environment.get_system_data_dirs ()) {
            var candidate = Path.build_filename (data_dir, "backgrounds", "centaur");
            if (FileUtils.test (candidate, FileTest.IS_DIR)) {
                return candidate;
            }
        }
        return null;
    }

    public static string? default_path () {
        var dir = centaur_dir ();
        if (dir == null) {
            return null;
        }
        var path = Path.build_filename (dir, DEFAULT_NAME);
        return FileUtils.test (path, FileTest.EXISTS) ? path : null;
    }

    /** Pictures the user added; copied here so moving the original is harmless. */
    public static string user_dir () {
        return Path.build_filename (Environment.get_user_data_dir (), "backgrounds");
    }

    /**
     * The image the wallpaper key actually means: the chosen file, or the
     * default when nothing is chosen or the chosen file has gone. Null only
     * when not even the default is installed.
     */
    public static string? resolve (string chosen) {
        if (chosen != "" && FileUtils.test (chosen, FileTest.IS_REGULAR)) {
            return chosen;
        }
        if (chosen != "") {
            Log.warn ("wallpaper %s is missing; using the default", chosen);
        }
        return default_path ();
    }

    /**
     * Every folder wallpapers are looked for in, Centaur's first. Includes
     * the conventional system locations other desktops install into, so
     * wallpaper packages show up without any Centaur-specific packaging.
     */
    public static string[] search_dirs () {
        string[] dirs = {};
        var own = centaur_dir ();
        if (own != null) {
            dirs += own;
        }
        dirs += user_dir ();
        foreach (var data_dir in Environment.get_system_data_dirs ()) {
            foreach (var name in new string[] { "backgrounds", "wallpapers" }) {
                var candidate = Path.build_filename (data_dir, name);
                if (FileUtils.test (candidate, FileTest.IS_DIR) && !(candidate in dirs)) {
                    dirs += candidate;
                }
            }
        }
        return dirs;
    }
}
