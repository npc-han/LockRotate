#!/bin/sh
# Run as root. Removes the helper and its sudoers rule; clears the lock-screen message
# unless --keep-text is given.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

[ "$(id -u)" -eq 0 ] || { echo "uninstall: must run as root" >&2; exit 77; }

rm -f /etc/sudoers.d/lockrotate
rm -rf /Library/PrivilegedHelperTools/lockrotate
rmdir /Library/PrivilegedHelperTools 2>/dev/null || true

if [ "${1:-}" != "--keep-text" ]; then
    defaults delete /Library/Preferences/com.apple.loginwindow LoginwindowText 2>/dev/null || true
fi
echo "uninstalled"
