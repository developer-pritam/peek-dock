import ApplicationServices
import Cocoa
import ScreenCaptureKit

struct WindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let app: NSRunningApplication
    var windowName: String?
    var image: CGImage?
    var axElement: AXUIElement
    var appAxElement: AXUIElement
    var frame: CGRect
    var isMinimized: Bool
    var isHidden: Bool
    var imageCapturedTime: Date
    var lastAccessedTime: Date

    init(
        id: CGWindowID,
        app: NSRunningApplication,
        windowName: String?,
        image: CGImage?,
        axElement: AXUIElement,
        appAxElement: AXUIElement,
        frame: CGRect,
        isMinimized: Bool,
        isHidden: Bool
    ) {
        self.id = id
        self.app = app
        self.windowName = windowName
        self.image = image
        self.axElement = axElement
        self.appAxElement = appAxElement
        self.frame = frame
        self.isMinimized = isMinimized
        self.isHidden = isHidden
        let now = Date()
        imageCapturedTime = now
        lastAccessedTime = now
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool { lhs.id == rhs.id }
}

// MARK: - Window Actions

extension WindowInfo {
    /// Closes the window via its AX close button.
    func close() {
        var closeBtn: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, "AXCloseButton" as CFString, &closeBtn)
        if let btn = closeBtn {
            AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString)
        }
    }

    /// Minimizes the window via AX.
    func minimize() {
        AXUIElementSetAttributeValue(axElement, kAXMinimizedAttribute as CFString, true as CFTypeRef)
    }

    /// Toggles fullscreen for the window via AX.
    func toggleFullscreen() {
        var val: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, "AXFullScreen" as CFString, &val)
        let current = (val as? Bool) ?? false
        AXUIElementSetAttributeValue(axElement, "AXFullScreen" as CFString, (!current) as CFTypeRef)
    }

    /// Brings this specific window to the front using SkyLight + AX APIs.
    func bringToFront() {
        let maxRetries = 3
        var retryCount = 0

        func attempt() -> Bool {
            do {
                var psn = ProcessSerialNumber()
                _ = GetProcessForPID(app.processIdentifier, &psn)
                _ = _SLPSSetFrontProcessWithOptions(&psn, UInt32(id), SLPSMode.userGenerated.rawValue)
                try axElement.performAction(kAXRaiseAction)
                try axElement.setAttribute(kAXMainWindowAttribute, true)
                return true
            } catch {
                return false
            }
        }

        while retryCount < maxRetries {
            if attempt() { return }
            retryCount += 1
            if retryCount < maxRetries { usleep(50_000) }
        }
    }
}
