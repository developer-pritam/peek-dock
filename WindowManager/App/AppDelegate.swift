import Cocoa
import ScreenCaptureKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panelCoordinator: PreviewPanelCoordinator?
    private var dockObserver: DockObserver?
    private var welcomeWindowController: WelcomeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Kill any previously running instance of PeekDock so the new binary
        // takes over cleanly. Must happen before any service setup.
        terminatePreviousInstances()

        // Re-register SMAppService if the user had Launch at Login enabled.
        // When the app binary is replaced the registration can become stale;
        // unregister + re-register silently refreshes it.
        refreshLoginItemIfNeeded()

        checkPermissions()
        setupStatusBar()
        setupPanelAndObserver()
        showWelcomeWindowIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyStatusBarVisibility),
            name: .peekDockStatusBarVisibilityChanged,
            object: nil
        )
    }

    // MARK: - Single-instance enforcement

    private func terminatePreviousInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        for app in others {
            app.terminate()
        }
    }

    // MARK: - Login item refresh

    private func refreshLoginItemIfNeeded() {
        guard #available(macOS 13, *) else { return }
        // Only touch the registration when it is currently enabled; this
        // re-points the login item to the new binary path automatically.
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
            try? SMAppService.mainApp.register()
        }
    }

    // MARK: - Permissions

    private func checkPermissions() {
        // Accessibility — prompt user immediately if not granted (required for Dock hover detection)
        if !AXIsProcessTrusted() {
            let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
            AXIsProcessTrustedWithOptions(opts)
        }

        // Screen Recording — trigger the OS permission dialog early by calling SCShareableContent.
        // We cannot use CGPreflightScreenCaptureAccess() as the gate — it returns false until the user
        // visits System Settings even if they've already granted permission in the current session.
        Task {
            _ = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        }
    }

    // MARK: - Status Bar

    @objc private func applyStatusBarVisibility() {
        let hide = UserDefaults.standard.bool(forKey: "hideStatusBarIcon")
        statusItem?.isVisible = !hide
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let button = statusItem?.button
        button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "PeekDock")
        button?.image?.isTemplate = true
        button?.action = #selector(statusBarClicked)
        button?.target = self
        applyStatusBarVisibility()
    }

    @objc private func statusBarClicked() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "PeekDock", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Permissions & About…",
                     action: #selector(showWelcomeWindow),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func showWelcomeWindow() {
        if welcomeWindowController == nil {
            welcomeWindowController = WelcomeWindowController()
        }
        welcomeWindowController?.show()
    }

    private func showWelcomeWindowIfNeeded() {
        // Show every launch — doubles as a live permissions & status page
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.showWelcomeWindow()
        }
    }

    // MARK: - Panel + Observer

    private func setupPanelAndObserver() {
        let panel = PreviewPanelCoordinator()
        panelCoordinator = panel
        dockObserver = DockObserver(panelCoordinator: panel)
    }
}
