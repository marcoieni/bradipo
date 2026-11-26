import Foundation
import Observation

@Observable @MainActor
final class BorderGlowIntensity {
    private static let defaultsKey = "borderGlowStrength"
    private let defaults: UserDefaults

    var value: Double {
        didSet { defaults.set(value, forKey: Self.defaultsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.object(forKey: Self.defaultsKey) as? Double, saved.isFinite {
            value = min(1, max(0, saved))
        } else {
            // The first half of the slider covers the original fixed-width glow.
            value = switch defaults.object(forKey: "borderGlowIntensity") as? Int {
            case 0: 0       // Off
            case 1: 0.125   // Low
            case 3: 0.5     // High
            default: 0.26   // Original glow (Medium)
            }
        }
    }

    var opacity: Double { min(1, value * 2) }
    private var spread: Double { max(0, value * 2 - 1) }
    var lineWidth: CGFloat { 22 + 234 * spread }
    var blurRadius: CGFloat { 12 + 32 * spread }
}
