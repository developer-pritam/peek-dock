import Cocoa

enum DockPosition {
    case top, bottom, left, right, unknown

    var isHorizontal: Bool {
        switch self {
        case .top, .bottom: true
        case .left, .right, .unknown: false
        }
    }
}

enum DockUtils {
    static func getDockPosition() -> DockPosition {
        var orientation: Int32 = 0
        var pinning: Int32 = 0
        CoreDockGetOrientationAndPinning(&orientation, &pinning)
        switch orientation {
        case 1: return .top
        case 2: return .bottom
        case 3: return .left
        case 4: return .right
        default: return .unknown
        }
    }

    /// Returns the Dock's height/width in screen points.
    static func getDockSize() -> CGFloat {
        guard let screen = NSScreen.main else { return 0 }
        switch getDockPosition() {
        case .bottom: return screen.visibleFrame.origin.y
        case .top:    return screen.frame.height - screen.visibleFrame.maxY
        case .left:   return screen.visibleFrame.origin.x
        case .right:  return screen.frame.width - screen.visibleFrame.width
        case .unknown: return 0
        }
    }
}
