# Security

LockRotate has to write `/Library/Preferences/com.apple.loginwindow`, which only root can do.
This page describes exactly what is installed with root rights, what it allows, and what it does not
protect against. Everything below can be checked against the files in this repository.

## Reporting a vulnerability

请通过 GitHub 私密安全公告（Security Advisories）报告：在本仓库的 Security 标签页点 "Report a vulnerability"。
Please report vulnerabilities privately through GitHub Security Advisories (the repository's
Security tab, "Report a vulnerability"), not in a public issue.

## What gets installed

"Install helper" (in the app, or `scripts/install.sh`) creates two things as root:

| Path | Owner / mode | Purpose |
|---|---|---|
| `/Library/PrivilegedHelperTools/lockrotate/set-lock-text` | `root:wheel`, 755 (directory 755 too) | The helper: writes the lock screen message. |
| `/etc/sudoers.d/lockrotate` | `root:wheel`, 0440 | Lets your user run that one helper without a password. |

The sudoers file contains one rule, with `<user>` replaced by your short user name:

```
<user> ALL=(root) NOPASSWD: /Library/PrivilegedHelperTools/lockrotate/set-lock-text ""
```

- It names one absolute path, with no wildcard. The trailing `""` means the helper may only be run
  with no arguments, so sudo refuses any attempt to pass any.
- The installer writes the rule to a temporary file and checks it with `visudo -cf`. It is moved into
  `/etc/sudoers.d/` only if that check passes.

## What the helper accepts

`set-lock-text` (36 lines, shell) does the following, in this order:

1. Refuses to run unless it is root, and refuses any command-line argument.
2. Sets `PATH=/usr/bin:/bin` and `LC_ALL=C`, and calls `defaults` by absolute path.
3. Reads the new text from **stdin**, not from arguments, so the text is not part of the `sudo` command line.
4. Rejects text longer than 2048 bytes.
5. Rejects any control character except newline (this includes ESC and DEL).
6. Rejects text that is not valid UTF-8, and text that is empty or only spaces and newlines.
7. Runs exactly two commands: `defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText -string <text>`
   and the same for `DisableLoginwindowText -bool false`. Nothing is passed through a shell.

Apart from standard text tools used for the checks (`head`, `wc`, `tr`, `grep`, `iconv`) it runs nothing else and reads no files. All it can do is set (or un-hide) the lock screen message.

## How the install is protected

- The app does not run a script from disk as root. It puts the install script and the helper into the
  command itself as inline base64 and runs it through `osascript ... with administrator privileges`,
  so root never executes or copies a file from a location the user can write to.
  `scripts/install.sh` does a similar thing: the helper travels as an inline base64 argument.
  (The CLI path does run `install-helper.sh` from your checkout under `sudo`, so it is your own
  copy of the file and your own password prompt; read it first if you are unsure.)
- The user name is checked against a whitelist (letters, digits, `_`, `.`, `-`, not `root`) both in
  the app and again in the install script, and the user must exist.
- Before writing anything, the install script checks that `/Library` and
  `/Library/PrivilegedHelperTools` are real directories, owned by root, and not writable by group or
  others. If not, it stops. A directory that someone else can write to would let them swap the helper
  after the sudoers rule was created.
- It only creates directories that are missing and never changes the owner or mode of existing ones.
- If any step after that fails, it deletes the sudoers file and the helper directory again
  ("rolled back"), so a half-finished install is not left behind.

## Threat model and what remains

What this protects against: a process that is not running as you cannot use the helper; the helper
cannot be used to run arbitrary commands, write other preferences or read files; the helper and its
directory cannot be replaced by a non-root user.

What it does **not** protect against:

- **Any process running as your user can change the lock screen message without a password**, by running
  `sudo -n /Library/PrivilegedHelperTools/lockrotate/set-lock-text` with text on stdin. The impact is
  limited to the message text (length- and character-checked, see above). But a lock screen message
  is something other people see, so it is a small way to put misleading text there.
- It does not defend against an attacker who already has root.
- It does not defend against someone who can modify `/Applications/LockRotate.app`: the app carries
  the helper and installer scripts, so a tampered app would install a tampered helper the next time
  you press "Install helper" and enter your password. Download releases only from this repository
  and compare the `.sha256` file.
- The release is ad-hoc signed and not notarized, so macOS cannot vouch for who built it.

If these trade-offs do not suit you, do not install the helper: the app still opens, but it cannot
change the message.

## Auditing it yourself

- The helper is `Sources/LockRotateSystem/Resources/set-lock-text` (36 lines). The installer is
  `Sources/LockRotateSystem/Resources/install-helper.sh`, the uninstaller `uninstall-helper.sh`.
  The app builds the commands in `Sources/LockRotateSystem/HelperCommands.swift`.
- Compare what is installed with the repository:
  ```sh
  ls -ld /Library /Library/PrivilegedHelperTools /Library/PrivilegedHelperTools/lockrotate
  ls -l  /Library/PrivilegedHelperTools/lockrotate/set-lock-text /etc/sudoers.d/lockrotate
  sudo cat /etc/sudoers.d/lockrotate
  diff /Library/PrivilegedHelperTools/lockrotate/set-lock-text Sources/LockRotateSystem/Resources/set-lock-text
  ```
- A built app contains the same scripts in
  `LockRotate.app/Contents/Resources/LockRotate_LockRotateSystem.bundle/Contents/Resources/`.

## Removing everything by hand

The app's "Uninstall helper" button and `scripts/uninstall.sh` do the same thing as these commands:

```sh
sudo rm -f /etc/sudoers.d/lockrotate
sudo rm -rf /Library/PrivilegedHelperTools/lockrotate
sudo rmdir /Library/PrivilegedHelperTools 2>/dev/null   # only removes it if it is empty
sudo defaults delete /Library/Preferences/com.apple.loginwindow LoginwindowText
```

(Skip the last command to keep the current message.) The helper also writes
`DisableLoginwindowText = false`; uninstalling does not touch that key. To remove it:
`sudo defaults delete /Library/Preferences/com.apple.loginwindow DisableLoginwindowText`.

Then delete `/Applications/LockRotate.app` and, if you want, `~/Library/Application Support/LockRotate`
(your list, settings and rotation state). Turn off "Open LockRotate at login" before deleting the app,
or remove it from System Settings → General → Login Items.
