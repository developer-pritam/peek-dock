import Cocoa
import SwiftUI

// MARK: - Preview Panel (NSPanel subclass)

final class PreviewPanelCoordinator: NSPanel {
    static weak var shared: PreviewPanelCoordinator?

    private var hideTimer: Timer?
    private var hideGraceTimer: Timer?
    var mouseIsInsidePanel: Bool = false

    private(set) var currentAppPID: pid_t?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing bufferingType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
    }

    convenience init() {
        let style: NSWindow.StyleMask = [.nonactivatingPanel, .fullSizeContentView, .borderless]
        self.init(contentRect: .zero, styleMask: style, backing: .buffered, defer: false)
        PreviewPanelCoordinator.shared = self
        setupPanel()
    }

    private func setupPanel() {
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none

        // Track mouse enter/exit for dismiss logic
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        contentView?.addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        mouseIsInsidePanel = true
        hideGraceTimer?.invalidate()
    }

    override func mouseExited(with event: NSEvent) {
        mouseIsInsidePanel = false
        scheduleHide()
    }

    // MARK: - Show / Hide

    @MainActor
    func showPreview(for app: NSRunningApplication, dockIconRect: CGRect, mouseLocation: NSPoint) {
        hideTimer?.invalidate()
        hideGraceTimer?.invalidate()
        currentAppPID = app.processIdentifier

        let cachedWindows = WindowCache.shared.read(pid: app.processIdentifier)

        let contentView = PreviewContentView(
            app: app,
            windows: cachedWindows,
            onTap: { [weak self] window in
                self?.handleWindowTap(window)
            },
            onMouseEntered: { [weak self] in
                self?.mouseIsInsidePanel = true
                self?.hideGraceTimer?.invalidate()
            },
            onMouseExited: { [weak self] in
                self?.mouseIsInsidePanel = false
                self?.scheduleHide()
            }
        )

        setSwiftUIContent(contentView, dockIconRect: dockIconRect, mouseLocation: mouseLocation)
        orderFront(nil)

        // Fetch fresh windows async
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let freshWindows = try await WindowUtil.getActiveWindows(of: app)
                await MainActor.run { [weak self] in
                    guard let self, self.currentAppPID == app.processIdentifier else { return }
                    let updatedView = PreviewContentView(
                        app: app,
                        windows: freshWindows,
                        onTap: { [weak self] window in self?.handleWindowTap(window) },
                        onMouseEntered: { [weak self] in
                            self?.mouseIsInsidePanel = true
                            self?.hideGraceTimer?.invalidate()
                        },
                        onMouseExited: { [weak self] in
                            self?.mouseIsInsidePanel = false
                            self?.scheduleHide()
                        }
                    )
                    self.setSwiftUIContent(updatedView, dockIconRect: dockIconRect, mouseLocation: mouseLocation)
                }
            } catch {
                print("[PreviewPanel] Failed to fetch windows: \(error)")
            }
        }
    }

    private func setSwiftUIContent(_ view: some View, dockIconRect: CGRect, mouseLocation: NSPoint) {
        let hostingView = NSHostingView(rootView: view)
        contentView = hostingView

        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let position = calculatePosition(
            for: fittingSize,
            dockIconRect: dockIconRect,
            mouseLocation: mouseLocation
        )
        setFrame(CGRect(origin: position, size: fittingSize), display: true)
    }

    func scheduleHide() {
        hideGraceTimer?.invalidate()
        hideGraceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            guard let self, !self.mouseIsInsidePanel else { return }
            self.hidePanel()
        }
    }

    func hidePanel() {
        hideTimer?.invalidate()
        hideGraceTimer?.invalidate()
        guard isVisible else { return }
        currentAppPID = nil
        contentView = nil
        orderOut(nil)
    }

    private func handleWindowTap(_ window: WindowInfo) {
        hidePanel()
        window.bringToFront()
    }

    // MARK: - Positioning

    private func calculatePosition(for panelSize: CGSize, dockIconRect: CGRect, mouseLocation: NSPoint) -> CGPoint {
        let screen = NSScreen.screenContainingMouse(mouseLocation) ?? NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.frame
        let dockPosition = DockUtils.getDockPosition()

        // Convert the Dock icon rect from AX (top-left origin) to AppKit (bottom-left origin)
        let flippedIconRect = CGRect(
            origin: DockObserver.cgPointFromNSPoint(dockIconRect.origin, forScreen: screen),
            size: dockIconRect.size
        )

        var x: CGFloat
        var y: CGFloat
        let buffer: CGFloat = 8

        switch dockPosition {
        case .bottom, .unknown:
            x = flippedIconRect.midX - panelSize.width / 2
            y = flippedIconRect.minY + buffer
        case .top:
            x = flippedIconRect.midX - panelSize.width / 2
            y = flippedIconRect.maxY - panelSize.height - buffer
        case .left:
            x = flippedIconRect.maxX + buffer
            y = flippedIconRect.midY - panelSize.height / 2
        case .right:
            x = flippedIconRect.minX - panelSize.width - buffer
            y = flippedIconRect.midY - panelSize.height / 2
        }

        // Clamp to screen bounds
        x = max(screenFrame.minX + 8, min(x, screenFrame.maxX - panelSize.width - 8))
        y = max(screenFrame.minY + 8, min(y, screenFrame.maxY - panelSize.height - 8))

        return CGPoint(x: x, y: y)
    }
}

// MARK: - NSScreen helper

extension NSScreen {
    static func screenContainingMouse(_ point: NSPoint) -> NSScreen? {
        screens.first { NSMouseInRect(point, $0.frame, false) } ?? main
    }
}
