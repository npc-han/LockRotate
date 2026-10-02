# Third-party notices

LockRotate is written from scratch in Swift. It does not contain copied code or text from the
projects below. They are listed because they shaped some design decisions, and one of them is
MIT-licensed, so its notice is included for good measure.

## Swift package dependencies

`Package.swift` declares no external dependencies. The app uses only Apple system frameworks
(Foundation, SwiftUI, AppKit, Combine, ServiceManagement) and the Swift Testing library that
ships with the toolchain.

## References

### nikolazleo/LoginwindowText-Updater

- Repository: https://github.com/nikolazleo/LoginwindowText-Updater
- Commit looked at: `876ce7d572bfe10fe7e9b94f10172ad930b48260`
- License: MIT, Copyright (c) 2026 nikolazleo
- What we took from it: ideas only. The form of the `defaults write` command for
  `LoginwindowText`, the idea of rotating through a list while skipping repeats, and the idea of a
  root-owned helper plus a sudoers rule so the rotation does not ask for a password each time.
  The code here (Swift app, helper script, installer) was written independently and differs
  in design (for example: the helper reads stdin, validates input, and the sudoers rule has no wildcard).

Its license text, included in case any of its expression is considered to have carried over:

```
MIT License

Copyright (c) 2026 nikolazleo

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Amorymeltzer/lockquote

- Repository: https://github.com/Amorymeltzer/lockquote
- Commit looked at: `72867052bceb74f3f98a3f1ef15804c261d40e62`
- License: the repository has no LICENSE file.
- What we took from it: the idea of putting a rotating line on the lock screen and of reading the
  current value with `defaults read` without elevated rights. No code and no quotations were
  copied. The example lists in `examples/` were written for this project.

### trilemma-dev/SwiftAuthorizationSample

- Repository: https://github.com/trilemma-dev/SwiftAuthorizationSample
- Commit looked at: `85f45622f819ca5b5dcf8867801a6b5d3edf63b2`
- License: MIT
- No code from it is used. It is kept as a reference for a possible future move from the
  sudoers-based helper to a privileged XPC helper.
