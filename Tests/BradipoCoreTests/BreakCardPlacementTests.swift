import BradipoCore
import CoreGraphics
import Foundation
import Testing

final class BreakCardPlacementTests {
    private let suite = "bradipo-tests-" + UUID().uuidString
    private let defaults: UserDefaults
    private let size = CGSize(width: 200, height: 60)

    init() { defaults = UserDefaults(suiteName: suite)! }

    deinit { defaults.removePersistentDomain(forName: suite) }

    private func placement(_ display: String, on screen: CGRect) -> BreakCardPlacement {
        BreakCardPlacement(displayID: display, visibleFrame: screen, cardSize: size, defaults: defaults)
    }

    @Test func cardPositionFollowsItsDisplayAcrossBreaksAndScreenChanges() {
        let screen = CGRect(x: -1000, y: 80, width: 1000, height: 660)

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
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let card = placement("built-in", on: screen)
        // A disconnected display has a saved position but no live card to reset.
        defaults.set([1.0, 1.0, 400.0, 150.0], forKey: "breakCardPosition.external")
        defaults.set(900, forKey: "workSeconds")
        #expect(BreakCardPlacement.canReset(in: defaults, visibleFrames: ["built-in": screen]) { size })
        _ = card.move(to: CGPoint(x: 10, y: 100))
        _ = card.resize(card.savedFrame, from: .topRight, by: CGVector(dx: 200, dy: 90))

        BreakCardPlacement.resetAll(in: defaults)
        let reconnected = placement("external", on: screen)
        let original = CGRect(x: 400, y: 22, width: 200, height: 60)
        #expect(card.savedFrame == original)
        #expect(reconnected.savedFrame == original)
        #expect(!BreakCardPlacement.canReset(in: defaults, visibleFrames: ["built-in": screen]) { size })
        #expect(defaults.integer(forKey: "workSeconds") == 900)
    }

    @Test func resetIsAvailableOnlyWhilePositionOrSizeDiffers() {
        let screen = CGRect(x: -815, y: 13, width: 815, height: 641)
        let card = placement("external", on: screen)
        let original = card.savedFrame
        func canReset() -> Bool {
            BreakCardPlacement.canReset(in: defaults, visibleFrames: ["external": screen]) { size }
        }
        #expect(!canReset())

        // Older builds could persist the default frame as normalized coordinates.
        defaults.set([(original.minX - screen.minX) / (screen.width - size.width),
                      (original.minY - screen.minY) / (screen.height - size.height),
                      size.width, size.height], forKey: "breakCardPosition.external")
        #expect(!canReset())
        _ = card.move(to: original.offsetBy(dx: 0.5, dy: 0).origin)
        #expect(canReset())
        _ = card.move(to: original.origin)
        #expect(!canReset())

        _ = card.resize(original, from: .top, by: CGVector(dx: 0, dy: 10))
        #expect(canReset())
        _ = card.resize(card.savedFrame, from: .top, by: CGVector(dx: 0, dy: -10))
        #expect(!canReset())
        // Returning to the default by hand should also clear it for a later disconnect.
        #expect(!BreakCardPlacement.canReset(in: defaults, visibleFrames: [:]) { size })
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
        let screen = CGRect(x: -1000, y: 40, width: 1000, height: 660)

        // Start from a centered position saved earlier on this display.
        defaults.set([0.5, 0.5, 200.0, 60.0], forKey: "breakCardPosition.external")
        let card = placement("external", on: screen)
        let start = card.savedFrame
        #expect(start == CGRect(x: -600, y: 340, width: 200, height: 60))
        // The mouse moves diagonally even on a straight edge, where only one axis should change.
        let resized = card.resize(start, from: handle, by: CGVector(dx: 30, dy: 10))
        #expect(resized == expected)
        #expect(placement("external", on: screen).savedFrame == resized)
        _ = card.move(to: screen.origin)
        #expect(placement("external", on: screen).savedFrame == CGRect(origin: screen.origin, size: resized.size))
        #expect(placement("other", on: screen).savedFrame.size == size)
    }

    @Test func cornerResizeStopsAtTheScreenEdgeAndMinimumReadableSize() {
        let screen = CGRect(x: 50, y: -500, width: 800, height: 500)
        let card = placement("small", on: screen)
        let start = CGRect(x: 150, y: -300, width: 200, height: 60)
        let large = card.resize(start, from: .topRight, by: CGVector(dx: 2000, dy: 2000))
        #expect(large == CGRect(x: 150, y: -300, width: 700, height: 300))
        // Pull past the opposite corner: the card stays upright and its contents stay readable.
        let small = card.resize(large, from: .bottomLeft, by: CGVector(dx: 3000, dy: 3000))
        #expect(small == CGRect(x: 700, y: -45, width: 150, height: 45))
    }
}
