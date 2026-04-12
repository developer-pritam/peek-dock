import ApplicationServices
import Cocoa

// Global C callback — AXObserver requires a plain C function pointer
func handleSelectedDockItemChangedNotification(
    observer _: AXObserver,
    element _: AXUIElement,
    notificationName _: CFString,
    context _: UnsafeMutableRawPointer?
) {
    DispatchQueue.main.async {
        DockObserver.shared?.processSelectedDockItemChanged()
    }
}

final class DockObserver {
    static weak var shared: DockObserver?

    private weak var panelCoordinator: PreviewPanelCoordinator?

    private var axObserver: AXObserver?
    private var currentDockPID: pid_t?
    private var subscribedDockList: AXUIElement?
    private var healthCheckTimer: Timer?

    init(panelCoordinator: PreviewPanelCoordinator) {
        self.panelCoordinator = panelCoordinator
        DockObserver.shared = self
        setupObserver()
        startHealthCheckTimer()
    }

    deinit {
        healthCheckTimer?.invalidate()
        teardownObserver()
    }

    // MARK: - Setup

    private func startHealthCheckTimer() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.performHealthCheck()
        }
    }

    private func performHealthCheck() {
        let currentDockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        if currentDockApp?.processIdentifier != currentDockPID {
            teardownObserver()
            setupObserver()
            return
        }
        // Verify the subscribed list element is still valid
        if let el = subscribedDockList {
            var role: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
            if result == .invalidUIElement || result == .cannotComplete {
                teardownObserver()
                setupObserver()
            }
        }
    }

    private func teardownObserver() {
        if let obs = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .commonModes)
        }
        axObserver = nil
        currentDockPID = nil
        subscribedDockList = nil
    }

    func setupObserver() {
        guard AXIsProcessTrusted() else {
            print("[DockObserver] Accessibility permission not granted")
            return
        }

        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return
        }

        let dockPID = dockApp.processIdentifier
        currentDockPID = dockPID

        let dockElement = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dockElement, 1.0)

        // Find the Dock's list element (the container for all Dock icons)
        guard let children = try? dockElement.children(),
              let axList = children.first(where: { (try? $0.role()) == kAXListRole })
        else {
            print("[DockObserver] Could not find Dock list element")
            return
        }

        if AXObserverCreate(dockPID, handleSelectedDockItemChangedNotification, &axObserver) != .success {
            print("[DockObserver] Failed to create AX observer")
            return
        }

        guard let axObserver else { return }

        do {
            try axList.subscribeToNotification(axObserver, kAXSelectedChildrenChangedNotification) {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver), .commonModes)
            }
            subscribedDockList = axList
        } catch {
            print("[DockObserver] Failed to subscribe to dock notifications: \(error)")
        }
    }

    // MARK: - Dock Item Detection

    /// Called by the AXObserver callback when the selected Dock item changes (i.e. hover changes).
    @MainActor
    func processSelectedDockItemChanged() {
        let mouseLocation = Self.getMousePosition()

        guard let hoveredDockItem = getHoveredAppDockItem() else {
            // Mouse moved away from an app icon
            panelCoordinator?.scheduleHide()
            return
        }

        // Get the NSRunningApplication for the hovered icon
        guard let appURL = try? hoveredDockItem.attribute(kAXURLAttribute, NSURL.self)?.absoluteURL else {
            panelCoordinator?.scheduleHide()
            return
        }

        let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier
        let runningApp: NSRunningApplication?

        if let bundleId = bundleIdentifier {
            runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
        } else {
            // Fallback: match by app name
            let name = try? hoveredDockItem.title()
            runningApp = name.flatMap { n in
                NSWorkspace.shared.runningApplications.first { $0.localizedName == n }
            }
        }

        guard let app = runningApp else {
            // App not running (not yet launched) — nothing to show
            panelCoordinator?.scheduleHide()
            return
        }

        // Get dock icon position/size for panel placement
        let dockIconRect = getDockItemRect(element: hoveredDockItem)

        // Show panel with cached windows first, then refresh async
        panelCoordinator?.showPreview(for: app, dockIconRect: dockIconRect, mouseLocation: mouseLocation)
    }

    private func getHoveredAppDockItem() -> AXUIElement? {
        guard let dockPID = currentDockPID else { return nil }

        let dockElement = AXUIElementCreateApplication(dockPID)

        // Get the first child of the Dock (the list element)
        var dockItems: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &dockItems) == .success,
              let dockItemsList = dockItems as? [AXUIElement],
              let dockList = dockItemsList.first
        else { return nil }

        // Get the selected (hovered) children
        var selectedChildren: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockList, kAXSelectedChildrenAttribute as CFString, &selectedChildren) == .success,
              let selected = selectedChildren as? [AXUIElement],
              let hoveredItem = selected.first
        else { return nil }

        // Only handle app icons (not the Trash, separators, etc.)
        guard (try? hoveredItem.subrole()) == "AXApplicationDockItem" else { return nil }

        return hoveredItem
    }

    private func getDockItemRect(element: AXUIElement) -> CGRect {
        guard let position = try? element.position(),
              let size = try? element.size()
        else { return .zero }
        return CGRect(origin: position, size: size)
    }

    // MARK: - Mouse Position

    static func getMousePosition() -> NSPoint {
        guard let event = CGEvent(source: nil) else { return .zero }
        let loc = event.location
        return NSPoint(x: loc.x, y: loc.y)
    }

    /// Convert a CGPoint (Quartz top-left origin) to NSPoint (AppKit bottom-left origin) for a given screen.
    static func nsPointFromCGPoint(_ point: CGPoint, forScreen screen: NSScreen?) -> NSPoint {
        guard let screen, let primary = NSScreen.screens.first else {
            return NSPoint(x: point.x, y: point.y)
        }
        let y: CGFloat
        if screen == primary {
            y = screen.frame.size.height - point.y
        } else {
            let offsetTop = primary.frame.height - (screen.frame.origin.y + screen.frame.height)
            let screenBottomOffset = primary.frame.height - (screen.frame.height + offsetTop)
            y = screen.frame.height + screenBottomOffset - (point.y - offsetTop)
        }
        return NSPoint(x: point.x, y: y)
    }

    /// Convert NSPoint (AppKit bottom-left) to CGPoint (Quartz top-left) for a given screen.
    static func cgPointFromNSPoint(_ point: CGPoint, forScreen screen: NSScreen?) -> CGPoint {
        guard let screen, let primary = NSScreen.screens.first else {
            return CGPoint(x: point.x, y: point.y)
        }
        let offsetTop = primary.frame.height - (screen.frame.origin.y + screen.frame.height)
        let menuScreenHeight = screen.frame.maxY
        return CGPoint(x: point.x, y: menuScreenHeight - point.y + offsetTop)
    }
}
