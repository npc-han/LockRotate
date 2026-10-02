import Foundation

// `--self-check` verifies bundled resources and localization, prints the result and exits
// without creating any UI. The packaging script runs it against the built .app.
if CommandLine.arguments.contains("--self-check") {
    exit(SelfCheck.run())
}

LockRotateMenuApp.main()
