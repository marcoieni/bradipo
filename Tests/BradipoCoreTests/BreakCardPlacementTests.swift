import BradipoCore
import CoreGraphics
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
    #expect(card.savedFrame.origin == CGPoint(x: -600, y: 102))
    let drop = CGPoint(x: -800, y: 530)
    #expect(card.move(to: drop) == drop)
    #expect(placement("external", on: screen).savedFrame.origin == drop)
    #expect(placement("built-in", on: screen).savedFrame.origin == CGPoint(x: -600, y: 102))

    // Keep the quarter-width, three-quarter-height placement after a display rearrangement.
    let changedScreen = CGRect(x: 20, y: -400, width: 600, height: 460)
    let restored = placement("external", on: changedScreen)
    #expect(restored.savedFrame.origin == CGPoint(x: 120, y: -100))

    // Dragging beyond the bottom-right edge should leave the entire card reachable.
    #expect(restored.move(to: CGPoint(x: 900, y: -500)) == CGPoint(x: 420, y: -400))
    #expect(placement("external", on: changedScreen).savedFrame.origin == CGPoint(x: 420, y: -400))
}

@Test func resetRestoresCurrentAndDisconnectedDisplays() {
    let suite = "bradipo-tests-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let size = CGSize(width: 200, height: 60)
    let card = BreakCardPlacement(displayID: "built-in", visibleFrame: screen, cardSize: size, defaults: defaults)
    _ = card.move(to: CGPoint(x: 10, y: 100))
    _ = card.resize(card.savedFrame, from: .topRight, by: CGVector(dx: 200, dy: 90))
    // A disconnected display has a saved position but no live card to reset.
    defaults.set([1.0, 1.0, 400.0, 150.0], forKey: "breakCardPosition.external")
    defaults.set(900, forKey: "workSeconds")

    BreakCardPlacement.resetAll(in: defaults)
    let reconnected = BreakCardPlacement(displayID: "external", visibleFrame: screen, cardSize: size, defaults: defaults)
    let original = CGRect(x: 400, y: 22, width: 200, height: 60)
    #expect(card.savedFrame == original)
    #expect(reconnected.savedFrame == original)
    #expect(defaults.integer(forKey: "workSeconds") == 900)
}

@Test(arguments: [
    (BreakCardPlacement.ResizeHandle.left, CGRect(x: -570, y: 340, width: 170, height: 60)),
    (.right, CGRect(x: -600, y: 340, width: 230, height: 60)),
    (.bottom, CGRect(x: -600, y: 350, width: 200, height: 50)),
    (.top, CGRect(x: -600, y: 340, width: 200, height: 70)),
    (.bottomLeft, CGRect(x: -570, y: 350, width: 170, height: 50)),
    (.bottomRight, CGRect(x: -600, y: 350, width: 230, height: 50)),
    (.topLeft, CGRect(x: -570, y: 340, width: 170, height: 70)),
    (.topRight, CGRect(x: -600, y: 340, width: 230, height: 70)),
])
func resizeMovesOnlyTheGrabbedEdgesAndPersists(handle: BreakCardPlacement.ResizeHandle, expected: CGRect) {
    let suite = "bradipo-tests-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let screen = CGRect(x: -1000, y: 40, width: 1000, height: 660)
    let size = CGSize(width: 200, height: 60)
    func placement(_ display: String = "external") -> BreakCardPlacement {
        BreakCardPlacement(displayID: display, visibleFrame: screen, cardSize: size, defaults: defaults)
    }

    // Start with a position saved by the move-only version of Bradipo.
    defaults.set([0.5, 0.5], forKey: "breakCardPosition.external")
    let card = placement()
    let start = card.savedFrame
    #expect(start == CGRect(x: -600, y: 340, width: 200, height: 60))
    // The mouse moves diagonally even on a straight edge, where only one axis should change.
    let resized = card.resize(start, from: handle, by: CGVector(dx: 30, dy: 10))
    #expect(resized == expected)
    #expect(placement().savedFrame == resized)
    _ = card.move(to: screen.origin)
    #expect(placement().savedFrame == CGRect(origin: screen.origin, size: resized.size))
    #expect(placement("other").savedFrame.size == size)
}

@Test func cornerResizeStopsAtTheScreenEdgeAndMinimumReadableSize() {
    let suite = "bradipo-tests-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let screen = CGRect(x: 50, y: -500, width: 800, height: 500)
    let card = BreakCardPlacement(displayID: "small", visibleFrame: screen,
                                  cardSize: CGSize(width: 200, height: 60), defaults: defaults)
    let start = CGRect(x: 150, y: -300, width: 200, height: 60)
    let large = card.resize(start, from: .topRight, by: CGVector(dx: 2000, dy: 2000))
    #expect(large == CGRect(x: 150, y: -300, width: 700, height: 300))
    // Pull past the opposite corner: the card stays upright and its contents stay readable.
    let small = card.resize(large, from: .bottomLeft, by: CGVector(dx: 3000, dy: 3000))
    #expect(small == CGRect(x: 700, y: -45, width: 150, height: 45))
}
