import AppKit
import SwiftUI

extension Color {
    /// Page background: black in dark mode, white in light mode.
    static let appBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
    })
}
