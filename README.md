# LockRotate

English | [简体中文](README.zh-CN.md)

A small macOS menu bar app that swaps the text of the "message to show when the screen is locked"
(System Settings → Lock Screen → "Show message when locked", stored as `LoginwindowText`) for the next entry of a list you provide.

## Features

- Import entries from a `.txt` or `.json` file, or add and edit them one by one in the app.
- Play them in order or shuffled. Shuffle goes through the whole list before repeating, and never shows the same entry twice in a row.
- Rotate on a timer (1 minute to 24 hours), when the Mac wakes, when the screen is unlocked, and once when the app starts. The "Next" button in the menu bar panel rotates right away.
- Pause automatic rotation; the pause is remembered across restarts.
- Optional "open at login".
- Clicking the menu bar icon opens a panel with a lock screen preview of the text that is showing right now, and its place in the list.
- English and Simplified Chinese interface.

## Install

### Pre-built release

1. Download `LockRotate-<version>-macos.zip` from the Releases page of this repository, and optionally check it against the `.sha256` file next to it (`shasum -a 256 -c LockRotate-<version>-macos.zip.sha256`).
2. Unzip it and drag `LockRotate.app` into `/Applications`.
3. The app is signed ad-hoc and **not notarized**, so macOS will refuse to open it the first time. Either:
   - open System Settings → Privacy & Security, scroll down, and click "Open Anyway" for LockRotate (on macOS 15 and later this is the way; on earlier versions right-click → Open also works), or
   - remove the quarantine flag in Terminal:
     ```sh
     xattr -dr com.apple.quarantine /Applications/LockRotate.app
     ```

### Build from source

You need a Swift 6 toolchain (Xcode or the command line tools) on macOS.

```sh
scripts/build-app.sh          # produces build/LockRotate.app
scripts/package-release.sh    # also produces build/LockRotate-<version>-macos.zip and a .sha256 file
```

Set `VERSION=1.2.3` to change the version number written into the app. No developer certificate is needed; the app is signed ad-hoc.

## First use

1. Click the menu bar icon, then "Settings…" in the panel.
2. Open the Authorization page and click "Authorize…" (the panel's main button says the same until this is done). macOS asks for your administrator password once.
   This installs a small root-owned script that can only set the lock screen message (see [Security model](#security-model)).
   Prefer the terminal? `scripts/install.sh` from a checkout does the same; run it as yourself, not with `sudo`.
3. On the List page, import a file (or add entries by hand).
4. Pick the order and the triggers on the Rotation page.

Until LockRotate is authorized the app can show the current message but cannot change it.

## List format

**Text** (`.txt`): one entry per line. Write `\n` inside a line for a line break. Blank lines and lines starting with `#` are ignored.

```
# comments start with #
Take your time. The email can wait ten minutes.
Stand up.\nLook at something far away.\nThen come back.
```

**JSON** (`.json`): an array of strings. (An object like `{"quotes": [...]}` also works.)

```json
["Take your time. The email can wait ten minutes.", "Stand up.\nLook at something far away.\nThen come back."]
```

Entries are tidied on import: control characters removed, blank lines collapsed, exact duplicates dropped, and each entry cut to at most 3 lines and 500 characters (the cut text ends with "…"). The app tells you how many were skipped, shortened or removed as duplicates.

Why 3 lines: a multi-line message is shown line by line on the lock screen, but when there is a lot of text the message box needs scrolling up and down to read it all.

Ready-made examples in [`examples/quotes.txt`](examples/quotes.txt) and [`examples/quotes.json`](examples/quotes.json) (the same 12 entries, written for this project).

## When it rotates

- **Order**: "In order" goes down the list and starts over; "Shuffle" plays the whole list in random order, then reshuffles, never starting a new pass with the entry that just ended the last one.
- **Timer**: every N minutes (default 30).
- **Wake**: about 3 seconds after the Mac wakes from sleep.
- **Unlock**: when the system announces that the screen was unlocked.
- **Start**: once when the app launches (if LockRotate is authorized, rotation is not paused and at least one trigger is on).
- Automatic triggers that arrive within 5 seconds of an earlier one are ignored, because a wake is usually followed by an unlock right away. "Next" in the panel is not affected.
- "Pause" in the panel stops all of the above, but "Next" still works.

Your list and settings are in `~/Library/Application Support/LockRotate`.

## Security model

Writing the lock screen message needs root, so authorizing LockRotate adds one helper script and one sudoers rule that lets your user run that script, and only that script, without a password. The script reads the text from stdin, limits it to 2048 bytes of valid UTF-8 without control characters (except newline), and does nothing except write the message.

The catch: any process running as your user can then change the lock screen message without asking. It cannot do anything else through this helper. Details, how to audit the 36-line helper and how to remove everything by hand are in [SECURITY.md](SECURITY.md).

## Uninstall

- In the app: Settings → Authorization → "Remove authorization…" (asks for your password; also clears the lock screen message), then delete `LockRotate.app`.
- Or from a checkout: `scripts/uninstall.sh` (add `--keep-text` to leave the current message in place).
- Turn off "Open LockRotate at login" before deleting the app. To also remove your list and settings, delete `~/Library/Application Support/LockRotate`.

## What has been tested

Tested by hand on macOS 26.6.2 (Apple Silicon):

- Writing `LoginwindowText` takes effect without `killall cfprefsd`. A multi-line message is shown line by line on the lock screen.
- Helper install, write and uninstall; "Authorize…" and "Remove authorization…" in the app; "Next"; a 1-minute timer; automatic rotation at app start; the pause setting surviving a restart.
- The unlock trigger and the 5-second de-duplication, using a simulated distributed notification.
- All 205 automated tests pass (`swift test`).

## Known limits

- Only tested on macOS 26.6.2 on Apple Silicon. The stated minimum is macOS 13, but 13 to 15 and Intel Macs have not been tried.
- A real lock → unlock and a real sleep → wake have **not** been tried on a device. The unlock trigger listens for `com.apple.screenIsUnlocked`, a notification Apple does not document; a macOS update could change or remove it. The timer, "Next" and the app-start rotation do not depend on it.
- "Open at login" uses `SMAppService.mainApp`, which expects the app to be in `/Applications`. How it behaves with an ad-hoc signed build has not been tested.
- The pre-built app is not notarized (see Install).
- Any process running as your user can change the lock screen message through the helper (text only, with length and character checks). See [SECURITY.md](SECURITY.md).

## Development

```sh
swift build
swift test
```

```
Sources/LockRotateCore/     list import, text cleaning, in-order/shuffle logic, settings and state files
Sources/LockRotateSystem/   helper scripts (Resources/), install/uninstall wrapper, reading the current text
Sources/LockRotateApp/      menu bar panel, settings window, triggers
Tests/                      tests for the three targets (Swift Testing)
scripts/                    build-app.sh, package-release.sh, install.sh, uninstall.sh
examples/                   sample lists
```

The package has no third-party dependencies. `.github/workflows/` holds a CI and a release workflow that have not been run yet.

## Credits

The idea of writing `LoginwindowText` from a sudoers-allowed helper and rotating through a list comes from [nikolazleo/LoginwindowText-Updater](https://github.com/nikolazleo/LoginwindowText-Updater) (MIT), and the idea of a rotating lock screen line from [Amorymeltzer/lockquote](https://github.com/Amorymeltzer/lockquote). No code or text was copied from either; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

[MIT](LICENSE)
