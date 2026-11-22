import CoreGraphics
import Foundation

public struct BreakCardPlacement {
    private let defaults: UserDefaults
    private let key: String
    // The area the card's lower-left corner can occupy while the whole card is visible.
    private let travel: CGRect

    public init(displayID: String, visibleFrame: CGRect, cardSize: CGSize, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "breakCardPosition." + displayID
        travel = CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                        width: max(0, visibleFrame.width - cardSize.width),
                        height: max(0, visibleFrame.height - cardSize.height))
    }

    public var savedOrigin: CGPoint {
        if let position = defaults.array(forKey: key) as? [Double], position.count == 2,
           (0...1).contains(position[0]), (0...1).contains(position[1]) {
            return CGPoint(x: travel.minX + travel.width * position[0],
                           y: travel.minY + travel.height * position[1])
        }
        return CGPoint(x: travel.midX.rounded(), y: min(travel.minY + 22, travel.maxY))
    }

    public func move(to origin: CGPoint) -> CGPoint {
        let x = min(max(origin.x, travel.minX), travel.maxX)
        let y = min(max(origin.y, travel.minY), travel.maxY)
        // Store fractions so moving or resizing the display preserves the relative position.
        defaults.set([travel.width > 0 ? (x - travel.minX) / travel.width : 0.5,
                      travel.height > 0 ? (y - travel.minY) / travel.height : 0], forKey: key)
        return CGPoint(x: x, y: y)
    }
}
