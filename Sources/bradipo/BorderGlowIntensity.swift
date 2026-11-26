import Foundation
import Observation

@Observable @MainActor
final class BorderGlowIntensity {
    private static let defaultsKey = "borderGlowStrength"

    var value: Double {
        didSet { UserDefaults.standard.set(value, forKey: Self.defaultsKey) }
    }

    init() {
        if let saved = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Double, saved.isFinite {
            value = min(1, max(0, saved))
        } else {
            // 0.26 draws the original glow (opacity 0.52, 22 pt line, 12 pt blur).
            // The first half of the slider changes only its opacity.
            value = 0.26
        }
    }

    var opacity: Double { min(1, value * 2) }
    private var spread: Double { max(0, value * 2 - 1) }
    var lineWidth: CGFloat { 22 + 234 * spread }
    var blurRadius: CGFloat { 12 + 32 * spread }
}
