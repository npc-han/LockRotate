import Foundation

public enum HelperPaths {
    public static let helperDirectory = "/Library/PrivilegedHelperTools/lockrotate"
    public static let helper = helperDirectory + "/set-lock-text"
    public static let sudoers = "/etc/sudoers.d/lockrotate"

    // Absolute paths so a poisoned PATH cannot redirect these.
    static let sudo = URL(fileURLWithPath: "/usr/bin/sudo")
    static let osascript = URL(fileURLWithPath: "/usr/bin/osascript")
}
