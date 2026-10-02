import Foundation

/// Looks the key up in this target's resource bundle. SwiftUI's default lookup uses
/// `Bundle.main`, which has no String Catalog for a SwiftPM resource bundle.
func loc(_ value: String.LocalizationValue) -> LocalizedStringResource {
    LocalizedStringResource(value, bundle: .atURL(Bundle.module.bundleURL))
}

/// Same lookup, resolved to a plain `String` (for model-level messages).
func localized(_ value: String.LocalizationValue) -> String {
    String(localized: loc(value))
}
