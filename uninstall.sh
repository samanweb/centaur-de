#!/usr/bin/env bash
#
# Removes a Centaur DE installed by install.sh.
#
# meson records every installed file, so this removes exactly what was put
# there and nothing else. It needs the build directory install.sh used.
#
set -euo pipefail

BUILD_DIR="${1:-build}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/${BUILD_DIR}/meson-logs/install-log.txt"

if [[ ! -f "${MANIFEST}" ]]; then
  printf '\033[31mNo install log at %s\033[0m\n' "${MANIFEST}"
  echo "Pass the build directory as the first argument, or remove the files by hand."
  exit 1
fi

echo "This will remove every file listed in ${MANIFEST}."
read -r -p "Continue? [y/N] " reply
[[ "${reply}" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

sudo systemctl disable --now centaur-sysd.service >/dev/null 2>&1 || true

# The log has a comment header; every other line is an installed path.
grep -v '^#' "${MANIFEST}" | while IFS= read -r path; do
  [[ -n "${path}" ]] || continue
  sudo rm -f "${path}"
done

sudo glib-compile-schemas /usr/share/glib-2.0/schemas 2>/dev/null || true
sudo systemctl daemon-reload 2>/dev/null || true

printf '\033[32mCentaur DE removed.\033[0m\n'
echo "Per-user configuration in ~/.config/centaur* and the dconf keys under"
echo "/org/centaur/ were left alone. Remove them with:"
echo "  dconf reset -f /org/centaur/"
