#!/usr/bin/env bash
#
# Centaur DE installer.
#
# Builds from this tree and installs system-wide. On Arch, prefer the package:
#     cd packaging/arch && makepkg -si
# because a package can be cleanly removed and this cannot.
#
#     ./install.sh --check     verify prerequisites, change nothing
#     ./install.sh             build and install
#     ./install.sh --prefix /opt/centaur
#
set -euo pipefail

PREFIX="/usr"
BUILD_DIR="build"
CHECK_ONLY=0
JOBS="$(nproc 2>/dev/null || echo 2)"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

usage() {
  sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)   CHECK_ONLY=1; shift ;;
    --prefix)  PREFIX="$2"; shift 2 ;;
    --prefix=*) PREFIX="${1#*=}"; shift ;;
    --build-dir) BUILD_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) red "unknown option: $1"; exit 2 ;;
  esac
done

# --- prerequisites ---------------------------------------------------------

missing_build=()
missing_runtime=()
missing_optional=()

need_program() {
  command -v "$1" >/dev/null 2>&1 || missing_build+=("$1")
}

need_pkgconfig() {
  pkg-config --exists "$1" 2>/dev/null || missing_runtime+=("$1")
}

want_program() {
  command -v "$1" >/dev/null 2>&1 || missing_optional+=("$1 — $2")
}

bold "Checking prerequisites"

need_program meson
need_program ninja
need_program valac
need_program pkg-config
need_program cc

if command -v pkg-config >/dev/null 2>&1; then
  need_pkgconfig gtk4
  need_pkgconfig gtk4-layer-shell-0
  need_pkgconfig glib-2.0
  need_pkgconfig gio-unix-2.0
  need_pkgconfig json-glib-1.0
  need_pkgconfig cairo
fi

want_program labwc   "the reference compositor (or install sway)"
want_program lsblk   "storage information on the Overview page"
want_program pactl   "the volume indicator"
want_program checkupdates "refreshing the update list on Arch (pacman-contrib)"
want_program python3 "the design-system test gates"

if ((${#missing_build[@]})); then
  red "Missing build tools: ${missing_build[*]}"
fi
if ((${#missing_runtime[@]})); then
  red "Missing development libraries: ${missing_runtime[*]}"
fi

if ((${#missing_build[@]} || ${#missing_runtime[@]})); then
  cat <<'HINT'

Install them with one of:

  Arch      sudo pacman -S vala meson ninja gtk4 gtk4-layer-shell json-glib \
                           cairo polkit util-linux
  Debian    sudo apt install valac meson ninja-build libgtk-4-dev \
                             libgtk4-layer-shell-dev libjson-glib-dev \
                             libcairo2-dev libpolkit-gobject-1-dev
  Fedora    sudo dnf install vala meson ninja-build gtk4-devel \
                             gtk4-layer-shell-devel json-glib-devel \
                             cairo-devel polkit-devel
  openSUSE  sudo zypper install vala meson ninja gtk4-devel \
                                gtk4-layer-shell-devel json-glib-devel \
                                cairo-devel polkit-devel

HINT
  exit 1
fi

green "All required build dependencies are present."

if ((${#missing_optional[@]})); then
  printf '\nOptional, and what you lose without each:\n'
  printf '  %b\n' "${missing_optional[@]}"
fi

if ((CHECK_ONLY)); then
  printf '\n'
  green "Check only: nothing was built or installed."
  exit 0
fi

# --- build -----------------------------------------------------------------

bold $'\nBuilding'

cd "${SCRIPT_DIR}"

if [[ -d "${BUILD_DIR}" ]]; then
  meson setup --reconfigure --prefix "${PREFIX}" "${BUILD_DIR}" app
else
  meson setup --prefix "${PREFIX}" "${BUILD_DIR}" app
fi

meson compile -C "${BUILD_DIR}" -j "${JOBS}"
meson test -C "${BUILD_DIR}" --print-errorlogs || red "tests failed (continuing)"

# --- install ---------------------------------------------------------------

bold $'\nInstalling'

if [[ $EUID -eq 0 ]]; then
  meson install -C "${BUILD_DIR}"
else
  sudo meson install -C "${BUILD_DIR}"
fi

cat <<MSG

$(green "Centaur DE is installed under ${PREFIX}.")

Next:
  1. sudo systemctl enable --now centaur-sysd.service
  2. Log out and choose "Centaur" in your display manager.

Uninstall with ./uninstall.sh (it uses ${BUILD_DIR}, so keep it).
MSG
