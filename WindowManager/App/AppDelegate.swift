import Cocoa
import ScreenCaptureKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panelCoordinator: PreviewPanelCoordinator?
    private var dockObserver: DockObserver?
    private var welcomeWindowController: WelcomeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        checkPermissions()
        setupStatusBar()
        setupPanelAndObserver()
        showWelcomeWindowIfNeeded()
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

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let button = statusItem?.button
        button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "PeekDock")
        button?.image?.isTemplate = true
        button?.action = #selector(statusBarClicked)
        button?.target = self
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
