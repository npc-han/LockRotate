import Foundation
import LockRotateCore
import LockRotateSystem

enum SelfCheck {
    private static let scripts = ["set-lock-text", "install-helper.sh", "uninstall-helper.sh"]

    /// Returns the process exit code: 0 when every check passed.
    static func run() -> Int32 {
        var failures = 0
        func report(_ ok: Bool, _ message: String) {
            print("\(ok ? "OK  " : "FAIL") \(message)")
            if !ok { failures += 1 }
        }

        print("app bundle: \(Bundle.main.bundlePath)")
        print("resource bundle: \(Bundle.module.bundlePath)")

        for name in scripts {
            do {
                let data = try HelperManager.bundledResource(name)
                report(!data.isEmpty, "helper resource \(name) (\(data.count) bytes)")
            } catch {
                report(false, "helper resource \(name): \(error.localizedDescription)")
            }
        }

        // The key is returned unchanged when the catalog is missing, so compare against it.
        let coreText = ImportError.emptyFile.errorDescription ?? ""
        report(!coreText.isEmpty && coreText != "import.error.emptyFile", "core localization: \(coreText)")
        let systemText = SystemError.helperNotInstalled.errorDescription ?? ""
        report(!systemText.isEmpty && systemText != "system.error.helperNotInstalled", "system localization: \(systemText)")

        var zh = loc("Next")
        zh.locale = Locale(identifier: "zh-Hans")
        let zhNext = String(localized: zh)
        report(zhNext == "下一条", "app localization zh-Hans: Next -> \(zhNext)")
        var en = loc("Next")
        en.locale = Locale(identifier: "en")
        report(String(localized: en) == "Next", "app localization en: Next -> \(String(localized: en))")

        var zhAuth = loc("Authorization")
        zhAuth.locale = Locale(identifier: "zh-Hans")
        report(String(localized: zhAuth) == "授权", "app localization zh-Hans: Authorization -> \(String(localized: zhAuth))")

        var zhCount = loc("\(3) entries")
        zhCount.locale = Locale(identifier: "zh-Hans")
        var enOne = loc("\(1) entries")
        enOne.locale = Locale(identifier: "en")
        report(String(localized: zhCount) == "3 条", "app plural zh-Hans: \(String(localized: zhCount))")
        report(String(localized: enOne) == "1 entry", "app plural en: \(String(localized: enOne))")

        print(failures == 0 ? "self-check passed" : "self-check failed (\(failures))")
        return failures == 0 ? 0 : 1
    }
}
