#!/bin/sh
# Command-line equivalent of "Install helper" in the LockRotate settings window, for people who
# prefer not to use the button.
#
# What it does: runs Sources/LockRotateSystem/Resources/install-helper.sh as root (via sudo,
# which asks for your password) and passes it your user name and the helper
# (Sources/LockRotateSystem/Resources/set-lock-text) as an inline base64 argument. The result:
#   /Library/PrivilegedHelperTools/lockrotate/set-lock-text   root:wheel 755
#   /etc/sudoers.d/lockrotate                                 root:wheel 440
# with one sudoers rule that lets YOUR USER run exactly that helper without a password.
# Read SECURITY.md first if you want the details.
#
# Usage: scripts/install.sh        (run it as yourself; do NOT prefix it with sudo)
set -eu

# Running the whole script under sudo would make "id -un" say root, and the sudoers rule would
# be written for the wrong user.
if [ "$(id -u)" -eq 0 ]; then
    echo "install.sh: do not run this script with sudo or as root." >&2
    echo "Run it as your normal user; it calls sudo itself for the one step that needs it." >&2
    exit 64
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
RES="$SCRIPT_DIR/../Sources/LockRotateSystem/Resources"
for f in install-helper.sh set-lock-text; do
    [ -f "$RES/$f" ] || { echo "install.sh: missing $RES/$f (run it from a full checkout)" >&2; exit 66; }
done

user=$(id -un)
helper_b64=$(base64 < "$RES/set-lock-text" | tr -d '\n')

echo "Installing the LockRotate helper for user '$user'. sudo may ask for your password."
sudo /bin/sh "$RES/install-helper.sh" "$user" "$helper_b64"
