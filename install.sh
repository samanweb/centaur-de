#!/usr/bin/env bash
#
# Centaur DE installer, for Arch Linux.
#
# Installs every package Centaur needs with pacman, builds this tree and
# installs it system-wide. The package list is packaging/arch/PKGBUILD's
# depends, makedepends and optdepends, so this and the Arch package always
# agree. (The package is the cleaner option: pacman can remove it again.
#     cd packaging/arch && makepkg -si )
#
#     ./install.sh --check     report what is missing, change nothing
#     ./install.sh             install packages, build and install Centaur
#     ./install.sh --prefix /opt/centaur
#     ./install.sh --no-optional      skip the optional packages
#
set -euo pipefail

PREFIX="/usr"
BUILD_DIR="build"
CHECK_ONLY=0
OPTIONAL=1
JOBS="$(nproc 2>/dev/null || echo 2)"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKGBUILD="${SCRIPT_DIR}/packaging/arch/PKGBUILD"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

usage() {
  sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)       CHECK_ONLY=1; shift ;;
    --prefix)      PREFIX="$2"; shift 2 ;;
    --prefix=*)    PREFIX="${1#*=}"; shift ;;
    --build-dir)   BUILD_DIR="$2"; shift 2 ;;
    --no-optional) OPTIONAL=0; shift ;;
    -h|--help)     usage ;;
    *) red "unknown option: $1"; exit 2 ;;
  esac
done

if [[ $EUID -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

# --- the package list --------------------------------------------------------

if ! command -v pacman >/dev/null 2>&1; then
  red "This installer installs Centaur's packages with pacman, and this system has none."
  echo "Centaur targets Arch Linux. On another distribution, install the equivalents"
  echo "of the depends, makedepends and optdepends in packaging/arch/PKGBUILD, then"
  echo "build with meson (see app/README.md)."
  exit 1
fi

# Read the three arrays from the PKGBUILD in a subshell: it is only variable
# and function definitions, and nothing it defines leaks into this script.
read_pkgbuild() {
  # shellcheck disable=SC1090
  ( source "${PKGBUILD}"; eval "printf '%s\n' \"\${$1[@]}\"" ) | sed 's/:.*//'
}
mapfile -t RUNTIME_PKGS < <(read_pkgbuild depends)
mapfile -t BUILD_PKGS   < <(read_pkgbuild makedepends)
mapfile -t OPTIONAL_PKGS < <(read_pkgbuild optdepends)

# makepkg assumes a compiler and pkg-config are there (base-devel); a plain
# ./install.sh cannot.
BUILD_PKGS+=(gcc pkgconf)

# Optional packages that are not installed, and why.
filtered=()
for pkg in "${OPTIONAL_PKGS[@]}"; do
  case "${pkg}" in
    sway)
      # An alternative compositor. labwc is Centaur's; installing a second
      # compositor nobody asked for is not "optional", it is clutter.
      continue ;;
    pipewire-pulse)
      # Conflicts with pulseaudio, and --noconfirm would turn that conflict
      # into a failed install. libpulse's pactl works with either server.
      if pacman -Q pulseaudio >/dev/null 2>&1; then
        continue
      fi ;;
  esac
  filtered+=("${pkg}")
done
OPTIONAL_PKGS=("${filtered[@]}")
((OPTIONAL)) || OPTIONAL_PKGS=()

# Prints the packages of a list that are not installed. pacman -T answers from
# the local database, resolving provides as well as names.
missing_from() {
  (($#)) || return 0
  pacman -T "$@" 2>/dev/null || true
}

mapfile -t MISSING_BUILD    < <(missing_from "${BUILD_PKGS[@]}")
mapfile -t MISSING_RUNTIME  < <(missing_from "${RUNTIME_PKGS[@]}")
mapfile -t MISSING_OPTIONAL < <(missing_from "${OPTIONAL_PKGS[@]}")

bold "Packages"
report() {
  local title="$1"; shift
  if (($#)); then
    printf '  %-10s missing: %s\n' "${title}" "$*"
  else
    printf '  %-10s all installed\n' "${title}"
  fi
}
report "build"    "${MISSING_BUILD[@]}"
report "required" "${MISSING_RUNTIME[@]}"
report "optional" "${MISSING_OPTIONAL[@]}"

if ((CHECK_ONLY)); then
  printf '\n'
  green "Check only: nothing was installed, built or changed."
  exit 0
fi

# --- install packages ----------------------------------------------------------

ALL_MISSING=("${MISSING_BUILD[@]}" "${MISSING_RUNTIME[@]}" "${MISSING_OPTIONAL[@]}")
if ((${#ALL_MISSING[@]})); then
  bold $'\nInstalling packages with pacman'
  # --needed: nothing already installed is reinstalled. No -y: syncing the
  # database without upgrading is Arch's partial-upgrade hazard, so a stale
  # database is reported instead of quietly half-upgraded.
  if ! "${SUDO[@]}" pacman -S --needed --noconfirm "${ALL_MISSING[@]}"; then
    red "pacman could not install: ${ALL_MISSING[*]}"
    echo "If the package database is stale, upgrade first and run this again:"
    echo "  sudo pacman -Syu"
    # Without the build tools there is nothing more to do; without an optional
    # package Centaur still runs, so only the first two are fatal.
    mapfile -t still < <(missing_from "${BUILD_PKGS[@]}" "${RUNTIME_PKGS[@]}")
    if ((${#still[@]})); then
      red "Still missing, and needed: ${still[*]}"
      exit 1
    fi
  fi
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

bold $'\nInstalling Centaur'

"${SUDO[@]}" meson install -C "${BUILD_DIR}"

# Base Center was removed in 0.1.1. meson only ever adds files, so an install
# over an older version would leave it in the application menu.
stale=(
  "${PREFIX}/bin/centaur-base-center"
  "${PREFIX}/share/applications/centaur-base-center.desktop"
)
for path in "${stale[@]}"; do
  if [[ -e "${path}" ]]; then
    "${SUDO[@]}" rm -f "${path}"
    echo "Removed ${path} (Base Center is no longer part of Centaur)"
  fi
done

# --- setting up --------------------------------------------------------------

bold $'\nSetting up'

# The compositor. centaur-session starts labwc; Centaur draws no windows
# itself, so without it the session cannot start at all.
if command -v labwc >/dev/null 2>&1; then
  echo "Compositor: labwc $(labwc --version 2>/dev/null | awk '{print $2}')"
else
  red "labwc is not installed: the Centaur session cannot start until it is."
fi

# The lock screen. Without its PAM service swaylock can lock but never
# authenticate, so the screen could not be unlocked. The swaylock package
# ships one; this covers a swaylock built from source. The content is
# upstream's own.
if command -v swaylock >/dev/null 2>&1; then
  pam=""
  for dir in /etc/pam.d /usr/lib/pam.d; do
    [[ -f "${dir}/swaylock" ]] && pam="${dir}/swaylock" && break
  done
  if [[ -z "${pam}" ]]; then
    printf '#\n# PAM configuration file for the swaylock screen locker.\n#\nauth include login\n' \
      | "${SUDO[@]}" tee /etc/pam.d/swaylock >/dev/null
    pam="/etc/pam.d/swaylock (created)"
  fi
  echo "Lock screen: swaylock, PAM service ${pam}"

  # The invoking user's home, not root's when run under sudo.
  user_home="$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)"
  for config in "${user_home}/.swaylock/config" "${user_home}/.config/swaylock/config"; do
    if [[ -f "${config}" ]]; then
      echo "  ${config} exists and takes precedence over Centaur's lock screen."
    fi
  done
fi

echo "Wallpaper: drawn by centaur-bg with swaybg; Centaur's are in ${PREFIX}/share/backgrounds/centaur"

# NetworkManager. The topbar's network indicator reads it, but switching a
# machine from another network service to it can drop the connection, so it
# is only enabled when nothing else is managing the network.
if pacman -Q networkmanager >/dev/null 2>&1 \
    && ! systemctl is-enabled --quiet NetworkManager.service 2>/dev/null; then
  other=""
  for service in systemd-networkd dhcpcd connman netctl iwd; do
    if systemctl is-active --quiet "${service}.service" 2>/dev/null; then
      other="${service}"
      break
    fi
  done
  if [[ -z "${other}" ]]; then
    "${SUDO[@]}" systemctl enable --now NetworkManager.service
    echo "Network: enabled NetworkManager"
  else
    echo "Network: ${other} manages the network, so NetworkManager was installed but"
    echo "  not enabled (both at once would fight over the connection). To switch:"
    echo "    sudo systemctl disable --now ${other}"
    echo "    sudo systemctl enable --now NetworkManager"
    echo "  Until then the topbar's network indicator stays hidden."
  fi
fi

# A virtual machine usually cannot wake from suspend and appears to hang, so
# the power menu hides Suspend there. Say so, rather than let it look missing.
if command -v systemd-detect-virt >/dev/null 2>&1 \
    && virt="$(systemd-detect-virt 2>/dev/null)" && [[ "${virt}" != "none" ]]; then
  echo "Suspend: hidden in the power menu under ${virt}, where a guest usually cannot"
  echo "  wake from it. To offer it anyway:"
  echo "    gsettings set org.centaur.topbar suspend-button always"
fi

# --- reload a running session --------------------------------------------

# A running topbar keeps executing the binary it started from, so without this
# nothing installed above is visible until the next login. centaur-session
# respawns any shell process that exits, so stopping them is the reload: they
# come back within a second from the new binaries. Only the invoking user's
# processes, and only under a live centaur-session.
SESSION_USER="${SUDO_USER:-$(id -un)}"
if pgrep -u "${SESSION_USER}" -f 'centaur-session --shell' >/dev/null 2>&1; then
  bold $'\nReloading the running session'
  for module in centaur-bg centaur-topbar centaur-settingsd; do
    # By command line, not -x: the kernel truncates process names to 15
    # characters, and "centaur-settingsd" is 17.
    if pkill -u "${SESSION_USER}" -f "(^|/)${module}( |$)" 2>/dev/null; then
      echo "Restarted ${module}"
    fi
  done

  # A session started by an older centaur-session does not supervise
  # centaur-bg, so nothing would bring the wallpaper up until the next login.
  # Start it for this session; from the next login the session owns it.
  timeout 1.5 tail -f /dev/null 2>/dev/null || true
  bg_helper="${PREFIX}/libexec/centaur-bg"
  if [[ -x "${bg_helper}" ]] \
      && ! pgrep -u "${SESSION_USER}" -f "(^|/)centaur-bg( |$)" >/dev/null 2>&1; then
    if [[ $EUID -ne 0 && -n "${WAYLAND_DISPLAY:-}" ]]; then
      setsid -f "${bg_helper}" >/dev/null 2>&1 < /dev/null
      echo "Started centaur-bg for this session"
    else
      echo "The wallpaper appears after you log out and back in."
    fi
  fi
fi

cat <<MSG

$(green "Centaur DE is installed under ${PREFIX}.")

Next:
  1. sudo systemctl enable --now centaur-sysd.service
  2. Log out and choose "Centaur" in your display manager.

Display settings: open "Displays" from the launcher (centaur-displays).
Wallpaper: open "Background" from the launcher (centaur-background).
Screenshots: Print (whole screen), Shift+Print (area), Super+Shift+S (options),
  or "Take Screenshot…" in the desktop menu. Saved to ~/Pictures/Screenshots
  and copied to the clipboard.

Uninstall with ./uninstall.sh (it uses ${BUILD_DIR}, so keep it).
MSG
