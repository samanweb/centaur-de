#!/usr/bin/env python3
"""Colour maths shared by the design-system tools. No dependencies."""

from __future__ import annotations


def srgb(hex_value: str) -> tuple[float, float, float]:
    h = hex_value.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def luminance(hex_value: str) -> float:
    def lin(c: float) -> float:
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(c) for c in srgb(hex_value))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(fg: str, bg: str) -> float:
    """WCAG 2.1 contrast ratio, 1.0 to 21.0."""
    a, b = luminance(fg), luminance(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def best_ink(background: str, *candidates: str) -> str:
    """Pick the candidate with the highest contrast against background."""
    return max(candidates, key=lambda c: ratio(c, background))


def mix(fg: str, bg: str, alpha: float) -> str:
    """fg painted over bg at `alpha`, as an opaque #rrggbb.

    For consumers that want solid colours where GTK would blend -- labwc, for
    one, draws menu highlights more cheaply and predictably when opaque.
    """
    f = [int(fg.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
    b = [int(bg.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
    return "#" + "".join(f"{round(fc * alpha + bc * (1 - alpha)):02x}" for fc, bc in zip(f, b))
