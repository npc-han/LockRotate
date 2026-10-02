#!/bin/sh
# Command-line equivalent of "Uninstall helper" in the LockRotate settings window.
#
# Runs Sources/LockRotateSystem/Resources/uninstall-helper.sh as root (via sudo, which asks for
# your password). It removes
#   /etc/sudoers.d/lockrotate
#   /Library/PrivilegedHelperTools/lockrotate/   (and the parent directory if it is then empty)
# and clears the lock screen message (LoginwindowText) unless you pass --keep-text.
#
# Usage: scripts/uninstall.sh [--keep-text]     (run it as yourself; do NOT prefix it with sudo)
set -eu

case "${1:-}" in
    ''|--keep-text) ;;
    *) echo "usage: uninstall.sh [--keep-text]" >&2; exit 64 ;;
esac
[ "$#" -le 1 ] || { echo "usage: uninstall.sh [--keep-text]" >&2; exit 64; }

if [ "$(id -u)" -eq 0 ]; then
    echo "uninstall.sh: do not run this script with sudo or as root." >&2
    echo "Run it as your normal user; it calls sudo itself for the one step that needs it." >&2
    exit 64
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
RES="$SCRIPT_DIR/../Sources/LockRotateSystem/Resources"
[ -f "$RES/uninstall-helper.sh" ] || { echo "uninstall.sh: missing $RES/uninstall-helper.sh (run it from a full checkout)" >&2; exit 66; }

echo "Removing the LockRotate helper. sudo may ask for your password."
sudo /bin/sh "$RES/uninstall-helper.sh" "$@"
