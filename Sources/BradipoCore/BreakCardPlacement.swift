import CoreGraphics
import Foundation

public struct BreakCardPlacement {
    public enum ResizeHandle: Sendable {
        case left, right, top, bottom, bottomLeft, bottomRight, topLeft, topRight

        // A zero component keeps that dimension fixed during an edge drag.
        fileprivate var direction: CGVector {
            switch self {
            case .left: CGVector(dx: -1, dy: 0)
            case .right: CGVector(dx: 1, dy: 0)
            case .top: CGVector(dx: 0, dy: 1)
            case .bottom: CGVector(dx: 0, dy: -1)
            case .bottomLeft: CGVector(dx: -1, dy: -1)
            case .bottomRight: CGVector(dx: 1, dy: -1)
            case .topLeft: CGVector(dx: -1, dy: 1)
            case .topRight: CGVector(dx: 1, dy: 1)
            }
        }
    }

    private static let keyPrefix = "breakCardPosition."
    private let defaults: UserDefaults
    private let key: String
    private let visibleFrame: CGRect
    private let defaultSize: CGSize

    public init(displayID: String, visibleFrame: CGRect, cardSize: CGSize, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = Self.keyPrefix + displayID
        self.visibleFrame = visibleFrame
        defaultSize = cardSize
    }

    public static func resetAll(in defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    public static func canReset(in defaults: UserDefaults = .standard, visibleFrames: [String: CGRect],
                                cardSize: () -> CGSize) -> Bool {
        lazy var size = cardSize()
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(keyPrefix) {
            guard let values = value as? [Double], hasStoredFrame(values) else { continue }
            let displayID = String(key.dropFirst(keyPrefix.count))
            // Reset also clears placements for disconnected displays.
            guard let visibleFrame = visibleFrames[displayID] else { return true }
            let card = Self(displayID: displayID, visibleFrame: visibleFrame, cardSize: size, defaults: defaults)
            if !card.isDefault(card.frame(from: values)) { return true }
        }
        return false
    }

    public var savedFrame: CGRect {
        frame(from: defaults.array(forKey: key) as? [Double] ?? [])
    }

    private static func hasStoredFrame(_ values: [Double]) -> Bool {
        values.count == 4 && values[2...].allSatisfy { $0.isFinite && $0 > 0 }
    }

    private var defaultFrame: CGRect { frame(from: []) }

    private func frame(from values: [Double]) -> CGRect {
        let hasSavedFrame = Self.hasStoredFrame(values)
        let requested = hasSavedFrame ? CGSize(width: values[2], height: values[3]) : defaultSize
        let size = constrainedSize(requested, maximum: visibleFrame.size)
        let travel = originRange(for: size)
        if hasSavedFrame, (0...1).contains(values[0]), (0...1).contains(values[1]) {
            return CGRect(x: travel.minX + travel.width * values[0], y: travel.minY + travel.height * values[1],
                          width: size.width, height: size.height)
        }
        return CGRect(x: travel.midX.rounded(), y: min(travel.minY + 22, travel.maxY),
                      width: size.width, height: size.height)
    }

    private func isDefault(_ frame: CGRect) -> Bool {
        let original = defaultFrame
        // Restoring a normalized origin can introduce a small rounding error.
        return frame.size == original.size && abs(frame.minX - original.minX) < 0.000001
            && abs(frame.minY - original.minY) < 0.000001
    }

    public func move(to origin: CGPoint) -> CGPoint {
        let size = savedFrame.size
        let travel = originRange(for: size)
        let x = min(max(origin.x, travel.minX), travel.maxX)
        let y = min(max(origin.y, travel.minY), travel.maxY)
        return save(CGRect(x: x, y: y, width: size.width, height: size.height)).origin
    }

    public func resize(_ frame: CGRect, from handle: ResizeHandle, by delta: CGVector) -> CGRect {
        let direction = handle.direction
        let movesLeft = direction.dx < 0
        let movesBottom = direction.dy < 0
        let anchorX = movesLeft ? frame.maxX : frame.minX
        let anchorY = movesBottom ? frame.maxY : frame.minY
        let maximum = CGSize(width: movesLeft ? anchorX - visibleFrame.minX : visibleFrame.maxX - anchorX,
                             height: movesBottom ? anchorY - visibleFrame.minY : visibleFrame.maxY - anchorY)
        let requested = CGSize(width: frame.width + direction.dx * delta.dx,
                               height: frame.height + direction.dy * delta.dy)
        let size = constrainedSize(requested, maximum: maximum)
        return save(CGRect(x: movesLeft ? anchorX - size.width : anchorX,
                           y: movesBottom ? anchorY - size.height : anchorY,
                           width: size.width, height: size.height))
    }

    private func constrainedSize(_ size: CGSize, maximum: CGSize) -> CGSize {
        // Keep the label readable when shrinking and the entire card reachable when enlarging.
        CGSize(width: min(maximum.width, max(defaultSize.width * 0.75, size.width)),
               height: min(maximum.height, max(defaultSize.height * 0.75, size.height)))
    }

    private func originRange(for size: CGSize) -> CGRect {
        CGRect(origin: visibleFrame.origin, size: CGSize(width: visibleFrame.width - size.width,
                                                        height: visibleFrame.height - size.height))
    }

    private func save(_ frame: CGRect) -> CGRect {
        if isDefault(frame) {
            defaults.removeObject(forKey: key)
            return defaultFrame
        }
        let travel = originRange(for: frame.size)
        let x = travel.width > 0 ? (frame.minX - travel.minX) / travel.width : 0.5
        let y = travel.height > 0 ? (frame.minY - travel.minY) / travel.height : 0
        defaults.set([min(1, max(0, x)), min(1, max(0, y)), frame.width, frame.height], forKey: key)
        return frame
    }
}
