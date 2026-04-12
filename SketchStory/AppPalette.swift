import SwiftUI

enum AppPalette {
    static let light = Color(red: 0.995, green: 0.931, blue: 0.833, opacity: 1.0)
    static let dark = Color(.systemBackground)

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? dark : light
    }

    static func contrast(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }

    static func card(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(.secondarySystemBackground) : .white.opacity(0.78)
    }
}
