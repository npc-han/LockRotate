#!/bin/sh
# Run as root. Usage: install-helper.sh <username> <helper-base64>
# The helper arrives as an argument (not a path) so root never executes or copies a file
# from a location the user can write to.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

DIR=/Library/PrivilegedHelperTools/lockrotate
HELPER=$DIR/set-lock-text
SUDOERS=/etc/sudoers.d/lockrotate

[ "$(id -u)" -eq 0 ] || { echo "install: must run as root" >&2; exit 77; }
[ "$#" -eq 2 ] || { echo "usage: install-helper.sh <username> <helper-base64>" >&2; exit 64; }
user=$1
helper_b64=$2

case $user in
    ''|root|*[!A-Za-z0-9_.-]*|[!A-Za-z_]*) echo "install: refusing username '$user'" >&2; exit 64 ;;
esac
id -u "$user" >/dev/null 2>&1 || { echo "install: no such user '$user'" >&2; exit 64; }

work=$(mktemp -d)
cleanup_work() { rm -rf "$work"; }
rollback() { rm -f "$SUDOERS"; rm -rf "$DIR"; }
trap cleanup_work EXIT
trap 'rollback; cleanup_work' INT TERM HUP

printf '%s' "$helper_b64" | base64 -D > "$work/helper"
head -n 1 "$work/helper" | grep -qx '#!/bin/sh' || { echo "install: helper payload looks wrong" >&2; exit 65; }
printf '%s ALL=(root) NOPASSWD: %s ""\n' "$user" "$HELPER" > "$work/sudoers"
visudo -cf "$work/sudoers" >/dev/null || { echo "install: sudoers rule failed validation" >&2; exit 65; }

# Only create what is missing, never chown or chmod directories that already exist.
[ -d /Library/PrivilegedHelperTools ] || install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools

# Every directory on the helper's path must be root-owned and not writable by group/other,
# otherwise a non-root process could swap the helper out from under the sudoers rule.
check_dir() {
    [ -d "$1" ] && [ ! -L "$1" ] || { echo "install: $1 is not a plain directory" >&2; return 1; }
    set -- "$1" "$(stat -f '%Su' "$1")" "$(stat -f '%Sp' "$1")"
    [ "$2" = root ] || { echo "install: $1 is not owned by root" >&2; return 1; }
    [ "$(printf '%s' "$3" | cut -c6)" = - ] && [ "$(printf '%s' "$3" | cut -c9)" = - ] \
        || { echo "install: $1 is writable by group/other" >&2; return 1; }
}
check_dir /Library && check_dir /Library/PrivilegedHelperTools || exit 1

# A failure after this point must not leave a half-installed state behind.
if ! {
    install -d -o root -g wheel -m 755 "$DIR" &&
    install -o root -g wheel -m 755 "$work/helper" "$HELPER" &&
    install -o root -g wheel -m 440 "$work/sudoers" "$SUDOERS"
}; then
    rollback
    echo "install: failed, rolled back" >&2
    exit 1
fi
echo "installed"
