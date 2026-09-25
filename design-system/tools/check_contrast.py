#!/usr/bin/env python3
"""Audit Centaur token contrast against WCAG 2.1.

Checks every text token against the surfaces it is allowed to sit on, and every
accent's ink against its own fill. Run as part of the design-system test suite.

Thresholds: 4.5 for body text, 3.0 for large text (>=20px) and for UI component
boundaries such as switch tracks and focus rings.
"""

from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BODY, LARGE = 4.5, 3.0


sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from color import best_ink, mix, ratio  # noqa: E402
from generate import MENU_HIGHLIGHT  # noqa: E402


# text token -> minimum required ratio. 'muted' and 'disabled' are deliberately
# held to the large-text threshold: they are only ever used for captions that
# repeat information available elsewhere, never for a label carrying meaning.
TEXT_RULES = {
    "primary": BODY,
    "secondary": BODY,
    "muted": LARGE,
    "disabled": 0.0,      # decorative by definition; excluded from the audit
}

SURFACES = ("window", "sidebar", "card", "raised", "overlay")


def main() -> int:
    data = json.loads((ROOT / "tokens.json").read_text())
    failures = []
    checks = 0

    for palette_name, palette in data["palettes"].items():
        for text_name, threshold in TEXT_RULES.items():
            if threshold == 0.0:
                continue
            fg = palette["text"][text_name]
            for surface_name in SURFACES:
                bg = palette["surface"][surface_name]
                checks += 1
                r = ratio(fg, bg)
                if r < threshold:
                    failures.append(
                        f"{palette_name}: text.{text_name} on surface.{surface_name} "
                        f"= {r:.2f} (need {threshold})"
                    )

        # Accent ink must be readable on its own accent fill.
        steps = palette["accent-steps"]
        for accent_name, accent in data["accents"].items():
            base = accent[steps["base"]]
            ink = best_ink(base, "#ffffff", accent["ink"])
            checks += 1
            r = ratio(ink, base)
            if r < BODY:
                failures.append(
                    f"{palette_name}: {accent_name} ink on accent fill "
                    f"= {r:.2f} (need {BODY})"
                )

        # labwc's highlighted menu item: primary text on the accent-tinted
        # overlay the generated themerc paints.
        overlay = palette["surface"]["overlay"]
        for accent_name, accent in data["accents"].items():
            highlight = mix(accent[steps["base"]], overlay, MENU_HIGHLIGHT)
            checks += 1
            r = ratio(palette["text"]["primary"], highlight)
            if r < BODY:
                failures.append(
                    f"{palette_name}: text.primary on {accent_name} menu highlight "
                    f"= {r:.2f} (need {BODY})"
                )

        # Accent as text on the card surface — used for selected sidebar rows.
        card = palette["surface"]["card"]
        for accent_name, accent in data["accents"].items():
            checks += 1
            r = ratio(accent[steps["base"]], card)
            if r < LARGE:
                failures.append(
                    f"{palette_name}: {accent_name} accent.base on surface.card "
                    f"= {r:.2f} (need {LARGE})"
                )

    for line in failures:
        print("FAIL " + line, file=sys.stderr)
    print(f"{checks - len(failures)}/{checks} contrast checks passed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
