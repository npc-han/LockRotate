# Changelog

## 0.1.0 - unreleased

First version.

- Menu bar app that rotates the macOS "Message to show when the screen is locked"
  text (`LoginwindowText`) through a list you import.
- Interface: clicking the menu bar icon opens a panel with a lock screen preview of the
  current text, its position in the list, and Next and Pause buttons. Settings is a window
  with a sidebar (List, Rotation, Authorization). Black, white and gray styling that follows
  light and dark mode.
- Import from a `.txt` file (one entry per line) or a `.json` file (array of strings);
  entries are cleaned, de-duplicated and limited to 3 lines / 500 characters by default.
- In-order and shuffle playback (shuffle never repeats an entry within one pass).
- Triggers: timer (1 to 1440 minutes), wake from sleep, screen unlock, and once when the
  app starts. Automatic triggers within 5 seconds of each other are collapsed into one.
  A "Next" button and a pause button in the menu bar panel.
- One-time authorization (administrator password) installs a small root-owned helper and one
  exact sudoers rule; "Authorize…" and "Remove authorization…" in the settings window, or
  `scripts/install.sh` / `scripts/uninstall.sh`.
- Optional "open at login" (uses `SMAppService`).
- English and Simplified Chinese interface.
- `scripts/build-app.sh` and `scripts/package-release.sh` build an ad-hoc signed,
  non-notarized `LockRotate.app` and a release zip with a SHA-256 file.
