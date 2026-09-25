namespace Centaur.Displays {

    /** One mode a display advertises. Refresh is in mHz, as the protocol has it. */
    public class Mode : Object {
        public int width { get; construct; }
        public int height { get; construct; }
        public int refresh { get; construct; }
        public bool preferred { get; construct; }

        public Mode (int width, int height, int refresh, bool preferred) {
            Object (width: width, height: height, refresh: refresh, preferred: preferred);
        }

        public string size_label () {
            return @"$width × $height";
        }

        /** "60 Hz", or "59.95 Hz" when the rate is not a whole number. */
        public string refresh_label () {
            if (refresh <= 0) {
                return "Default";
            }
            if (refresh % 1000 == 0) {
                return @"$(refresh / 1000) Hz";
            }
            return "%.2f Hz".printf (refresh / 1000.0);
        }
    }

    /**
     * One display, as a plain value.
     *
     * The window edits copies and the compositor's latest snapshot stays
     * untouched, so reverting is a matter of re-applying the snapshot.
     */
    public class Head : Object {
        public string name = "";
        public string description = "";
        public string make = "";
        public string model = "";
        public string serial = "";
        public int width_mm;
        public int height_mm;
        public bool enabled;
        public int x;
        public int y;
        public int transform;
        public double scale = 1.0;
        public int current = -1;
        public Mode[] modes = {};

        public static Head from_variant (Variant props) {
            var dict = new VariantDict (props);
            var head = new Head ();

            dict.lookup ("name", "s", out head.name);
            dict.lookup ("description", "s", out head.description);
            dict.lookup ("make", "s", out head.make);
            dict.lookup ("model", "s", out head.model);
            dict.lookup ("serial", "s", out head.serial);
            dict.lookup ("width-mm", "i", out head.width_mm);
            dict.lookup ("height-mm", "i", out head.height_mm);
            dict.lookup ("enabled", "b", out head.enabled);
            dict.lookup ("x", "i", out head.x);
            dict.lookup ("y", "i", out head.y);
            dict.lookup ("transform", "i", out head.transform);
            dict.lookup ("scale", "d", out head.scale);
            dict.lookup ("current", "i", out head.current);

            var modes = dict.lookup_value ("modes", new VariantType ("a(iiib)"));
            if (modes != null) {
                Mode[] list = {};
                foreach (var mode in modes) {
                    int w, h, r;
                    bool preferred;
                    mode.get ("(iiib)", out w, out h, out r, out preferred);
                    list += new Mode (w, h, r, preferred);
                }
                head.modes = list;
            }
            return head;
        }

        public Head copy () {
            var head = new Head ();
            head.name = name;
            head.description = description;
            head.make = make;
            head.model = model;
            head.serial = serial;
            head.width_mm = width_mm;
            head.height_mm = height_mm;
            head.enabled = enabled;
            head.x = x;
            head.y = y;
            head.transform = transform;
            head.scale = scale;
            head.current = current;
            head.modes = modes;
            return head;
        }

        /**
         * What a saved setting is keyed by.
         *
         * Make, model and serial follow the monitor from port to port. Without
         * a serial -- common on cheap panels and on every virtual display --
         * the connector name is the best there is.
         */
        public string identity {
            owned get {
                var last = serial != "" ? serial : name;
                return @"$make|$model|$last";
            }
        }

        /** "Dell U2720Q", falling back through what the display reported. */
        public string title {
            owned get {
                var product = @"$make $model".strip ();
                if (product != "") {
                    return product;
                }
                return description != "" ? description : name;
            }
        }

        public Mode? current_mode () {
            return current >= 0 && current < modes.length ? modes[current] : null;
        }

        public Mode? preferred_mode () {
            foreach (var mode in modes) {
                if (mode.preferred) {
                    return mode;
                }
            }
            return modes.length > 0 ? modes[0] : null;
        }

        public int preferred_index () {
            for (var i = 0; i < modes.length; i++) {
                if (modes[i].preferred) {
                    return i;
                }
            }
            return modes.length > 0 ? 0 : -1;
        }

        /** The mode actually in use, or the one enabling would pick. */
        public Mode? effective_mode () {
            return current_mode () ?? preferred_mode ();
        }

        public bool rotated {
            get { return transform % 2 == 1; }
        }

        /** Size in the layout's coordinates: after rotation and scale. */
        public int logical_width {
            get {
                var mode = effective_mode ();
                if (mode == null) {
                    return 0;
                }
                var pixels = rotated ? mode.height : mode.width;
                return (int) Math.round (pixels / scale);
            }
        }

        public int logical_height {
            get {
                var mode = effective_mode ();
                if (mode == null) {
                    return 0;
                }
                var pixels = rotated ? mode.width : mode.height;
                return (int) Math.round (pixels / scale);
            }
        }

        /**
         * The index of the mode matching a size, at the refresh closest to the
         * one asked for; -1 when no mode has that size.
         */
        public int find_mode (int width, int height, int refresh) {
            var best = -1;
            var best_distance = int.MAX;
            for (var i = 0; i < modes.length; i++) {
                if (modes[i].width != width || modes[i].height != height) {
                    continue;
                }
                var distance = (modes[i].refresh - refresh).abs ();
                if (distance < best_distance) {
                    best = i;
                    best_distance = distance;
                }
            }
            return best;
        }

        public bool same_state (Head other) {
            return enabled == other.enabled
                && (!enabled || (current == other.current
                                 && x == other.x && y == other.y
                                 && transform == other.transform
                                 && Math.fabs (scale - other.scale) < 0.001));
        }
    }

    public Head[] parse (Variant snapshot) {
        Head[] heads = {};
        foreach (var props in snapshot) {
            heads += Head.from_variant (props);
        }
        return heads;
    }

    public Head[] copy_all (Head[] heads) {
        Head[] copies = {};
        foreach (var head in heads) {
            copies += head.copy ();
        }
        return copies;
    }

    /** The aa{sv} OutputManager.apply takes. Every head is spelled out. */
    public Variant build_config (Head[] heads) {
        var builder = new VariantBuilder (new VariantType ("aa{sv}"));
        foreach (var head in heads) {
            var props = new VariantDict ();
            props.insert ("name", "s", head.name);
            props.insert ("enabled", "b", head.enabled);
            if (head.enabled) {
                var mode = head.current >= 0 ? head.current : head.preferred_index ();
                props.insert ("mode", "i", mode);
                props.insert ("x", "i", head.x);
                props.insert ("y", "i", head.y);
                props.insert ("transform", "i", head.transform);
                props.insert ("scale", "d", head.scale);
            }
            builder.add_value (props.end ());
        }
        return builder.end ();
    }

    /**
     * Moves the layout so its top-left enabled display sits at 0,0.
     *
     * Compositors accept negative positions, but a layout that drifts a little
     * further from the origin with every drag is confusing to read back.
     */
    public void normalize (Head[] heads) {
        var min_x = int.MAX;
        var min_y = int.MAX;
        foreach (var head in heads) {
            if (head.enabled) {
                min_x = int.min (min_x, head.x);
                min_y = int.min (min_y, head.y);
            }
        }
        if (min_x == int.MAX) {
            return;
        }
        foreach (var head in heads) {
            if (head.enabled) {
                head.x -= min_x;
                head.y -= min_y;
            }
        }
    }

    public bool all_same (Head[] a, Head[] b) {
        if (a.length != b.length) {
            return false;
        }
        for (var i = 0; i < a.length; i++) {
            if (a[i].name != b[i].name || !a[i].same_state (b[i])) {
                return false;
            }
        }
        return true;
    }
}
