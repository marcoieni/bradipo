import BradipoCore
import Foundation
import Testing

@Test func cardPositionFollowsItsDisplayAcrossBreaksAndScreenChanges() {
    let suite = "bradipo-tests-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let size = CGSize(width: 200, height: 60)
    let screen = CGRect(x: -1000, y: 80, width: 1000, height: 660)
    func placement(_ display: String, on frame: CGRect) -> BreakCardPlacement {
        BreakCardPlacement(displayID: display, visibleFrame: frame, cardSize: size, defaults: defaults)
    }

    let card = placement("external", on: screen)
    #expect(card.savedOrigin == CGPoint(x: -600, y: 102))
    let drop = CGPoint(x: -800, y: 530)
    #expect(card.move(to: drop) == drop)
    #expect(placement("external", on: screen).savedOrigin == drop)
    #expect(placement("built-in", on: screen).savedOrigin == CGPoint(x: -600, y: 102))

    // Keep the quarter-width, three-quarter-height placement after a display rearrangement.
    let changedScreen = CGRect(x: 20, y: -400, width: 600, height: 460)
    let restored = placement("external", on: changedScreen)
    #expect(restored.savedOrigin == CGPoint(x: 120, y: -100))

    // Dragging beyond the bottom-right edge should leave the entire card reachable.
    #expect(restored.move(to: CGPoint(x: 900, y: -500)) == CGPoint(x: 420, y: -400))
    #expect(placement("external", on: changedScreen).savedOrigin == CGPoint(x: 420, y: -400))
}
