import SwiftUI
import ApplicationServices
import ServiceManagement

extension Notification.Name {
    static let peekDockStatusBarVisibilityChanged = Notification.Name("PeekDockStatusBarVisibilityChanged")
}

private let kPortfolioURL = URL(string: "https://developerpritam.in")!
private let kDonationURL  = URL(string: "https://developerpritam.in/donate")!

// MARK: - Window Controller

final class WelcomeWindowController: NSWindowController, NSWindowDelegate {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "PeekDock"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 480, height: 480)
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WelcomeView { window.close() })
        self.init(window: window)
        window.delegate = self
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Tab enum

private enum SettingsTab: String, Hashable {
    case getStarted  = "Get Started"
    case preferences = "Preferences"
    case howToUse    = "How to Use"
}

// MARK: - Root View

struct WelcomeView: View {
    let close: () -> Void

    @State private var selectedTab: SettingsTab = .getStarted
    @State private var accessibilityGranted   = false
    @State private var screenRecordingGranted = false
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)

    @AppStorage("hideStatusBarIcon")    private var hideStatusBarIcon:    Bool   = false
    @AppStorage("showPreviewHeader")    private var showPreviewHeader:    Bool   = true
    @AppStorage("showMinimizedWindows") private var showMinimizedWindows: Bool   = true
    @AppStorage("showMinimizedBadge")   private var showMinimizedBadge:   Bool   = true
    @AppStorage("thumbnailScale")       private var thumbnailScale:       Double = 1.0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Dynamic tab list

    private var allPermissionsGranted: Bool {
        accessibilityGranted && screenRecordingGranted
    }

    /// Tabs change based on whether permissions have been granted.
    private var availableTabs: [SettingsTab] {
        allPermissionsGranted
            ? [.preferences, .howToUse]
            : [.getStarted,  .preferences]
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            tabBar
            Divider()
            tabContent
            Divider()
            footerSection
        }
        .frame(width: 480)
        .frame(maxHeight: .infinity)
        .onAppear { refreshPermissions() }
        .onReceive(timer) { _ in refreshPermissions() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("PeekDock").font(.title3).fontWeight(.semibold)
                    Text("v\(appVersion)")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                Text("Instant window previews, right from your Dock")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        Picker("", selection: $selectedTab.animation(.easeInOut(duration: 0.18))) {
            ForEach(availableTabs, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch selectedTab {
                case .getStarted:  getStartedContent
                case .preferences: preferencesContent
                case .howToUse:    howToUseContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Get Started (permissions + how-to-use combined)

    private var getStartedContent: some View {
        VStack(spacing: 0) {
            sectionLabel("Permissions")
            permissionsRows
            Divider()
            sectionLabel("How to Use")
            howToUseSteps
        }
    }

    // MARK: - Preferences tab

    private var preferencesContent: some View {
        VStack(spacing: 0) {
            sectionLabel("Preview Size")
            thumbnailSizeRow
            Divider().padding(.leading, 54)

            sectionLabel("Display")
            PreferenceRow(icon: "text.badge.checkmark", iconColor: .blue,
                          title: "Show app header in preview",
                          description: "Displays the app name and window count above the grid.") {
                Toggle("", isOn: $showPreviewHeader).toggleStyle(.switch).labelsHidden()
            }
            Divider().padding(.leading, 54)
            PreferenceRow(icon: "minus.circle", iconColor: .indigo,
                          title: "Show minimized windows",
                          description: "Include minimized windows in the preview panel.") {
                Toggle("", isOn: $showMinimizedWindows).toggleStyle(.switch).labelsHidden()
            }
            if showMinimizedWindows {
                Divider().padding(.leading, 74)
                PreferenceRow(icon: "tag", iconColor: .indigo,
                              title: "Show \u{201C}Minimized\u{201D} badge",
                              description: "Label thumbnails of minimized windows.",
                              isSubOption: true) {
                    Toggle("", isOn: $showMinimizedBadge).toggleStyle(.switch).labelsHidden()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            sectionLabel("System")
            PreferenceRow(icon: "arrow.circlepath", iconColor: .green,
                          title: "Launch at Login",
                          description: "Automatically start PeekDock when you log in.") {
                Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).labelsHidden()
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else       { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                        }
                    }
            }
            Divider().padding(.leading, 54)
            PreferenceRow(icon: "menubar.rectangle", iconColor: .secondary,
                          title: "Hide menu bar icon",
                          description: "PeekDock still runs in the background. Reopen by relaunching the app.") {
                Toggle("", isOn: $hideStatusBarIcon).toggleStyle(.switch).labelsHidden()
                    .onChange(of: hideStatusBarIcon) { _ in
                        NotificationCenter.default.post(
                            name: .peekDockStatusBarVisibilityChanged, object: nil)
                    }
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.15), value: showMinimizedWindows)
    }

    // MARK: - How to Use tab

    private var howToUseContent: some View {
        VStack(spacing: 0) {
            sectionLabel("Quick Start")
            howToUseSteps
            Divider()
            sectionLabel("Window Actions")
            VStack(alignment: .leading, spacing: 14) {
                StepRow(number: nil, icon: "xmark.circle.fill",
                        title: "Close",
                        text: "Hover a thumbnail to reveal traffic-light buttons. Red × closes the window.")
                StepRow(number: nil, icon: "minus.circle.fill",
                        title: "Minimize",
                        text: "Yellow – minimizes the window to the Dock.")
                StepRow(number: nil, icon: "arrow.up.left.and.arrow.down.right.circle.fill",
                        title: "Full Screen",
                        text: "Green ↗ toggles full-screen mode for that window.")
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
    }

    // MARK: - Shared sub-views

    /// Permission rows reused inside Get Started and standalone
    private var permissionsRows: some View {
        VStack(spacing: 0) {
            PermissionRow(
                icon: "accessibility", iconColor: .blue,
                title: "Accessibility",
                description: "Lets the app watch the Dock for hover events and detect which app icon your cursor is over. Without this the preview panel cannot appear.",
                isGranted: accessibilityGranted,
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
            Divider().padding(.leading, 54)
            PermissionRow(
                icon: "video.fill", iconColor: .purple,
                title: "Screen Recording",
                description: "Captures live thumbnail images of each open window. Only used to render previews — no content is stored or transmitted.",
                isGranted: screenRecordingGranted,
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            )
        }
    }

    /// How-to-use steps reused inside Get Started and How to Use tab
    private var howToUseSteps: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepRow(number: 1, icon: "cursorarrow.click",
                    title: "Hover a Dock icon",
                    text: "Hover any app icon in your Dock — even ones with multiple windows open.")
            StepRow(number: 2, icon: "square.grid.2x2",
                    title: "Preview panel appears",
                    text: "A panel pops up showing all open windows for that app as live thumbnails.")
            StepRow(number: 3, icon: "arrow.up.right.square",
                    title: "Click to switch",
                    text: "Click any thumbnail to instantly bring that exact window to front.")
        }
        .padding(.horizontal, 24).padding(.bottom, 20)
    }

    // MARK: - Thumbnail size row

    private var thumbnailSizeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.teal.opacity(0.13)).frame(width: 34, height: 34)
                    Image(systemName: "square.resize")
                        .font(.system(size: 14, weight: .medium)).foregroundColor(.teal)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Thumbnail Size").font(.system(size: 13, weight: .semibold))
                    Text(sizeLabel).font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Image(systemName: "rectangle.compress.vertical")
                    .font(.system(size: 10)).foregroundColor(.secondary).frame(width: 14)
                Slider(value: $thumbnailScale, in: 0.75...1.5, step: 0.25).labelsHidden()
                Image(systemName: "rectangle.expand.vertical")
                    .font(.system(size: 10)).foregroundColor(.secondary).frame(width: 14)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private var sizeLabel: String {
        switch thumbnailScale {
        case ..<0.875: return "Small  (minimum)"
        case ..<1.125: return "Medium"
        case ..<1.375: return "Large"
        default:       return "X-Large"
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 10) {
            LinkButton(label: "Buy me a coffee", systemIcon: "cup.and.saucer.fill",
                       color: .orange, url: kDonationURL)
            LinkButton(label: "Portfolio", systemIcon: "globe",
                       color: .blue, url: kPortfolioURL)
            Spacer()
            if !allPermissionsGranted {
                Text("Permissions required")
                    .font(.caption).foregroundColor(.orange)
            }
            Button("Done") { close() }
                .keyboardShortcut(.defaultAction).controlSize(.large)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary).tracking(0.8)
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 8)
    }

    private func refreshPermissions() {
        let wasAllGranted = allPermissionsGranted
        accessibilityGranted   = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        let nowAllGranted = allPermissionsGranted

        // Auto-switch tab when permissions become fully granted
        if nowAllGranted && !wasAllGranted {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = .preferences }
        }

        // If current tab is no longer in the available list, snap to first available
        if !availableTabs.contains(selectedTab) {
            selectedTab = availableTabs[0]
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Preference Row

private struct PreferenceRow<Control: View>: View {
    let icon: String; let iconColor: Color
    let title: String; let description: String
    var isSubOption: Bool = false
    @ViewBuilder let control: () -> Control

    private var iconSize: CGFloat { isSubOption ? 28 : 34 }
    private var cornerR:  CGFloat { isSubOption ?  7 :  9 }
    private var fontSize: CGFloat { isSubOption ? 12 : 13 }
    private var vPad:     CGFloat { isSubOption ?  8 : 10 }
    private var leadPad:  CGFloat { isSubOption ? 44 : 24 }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerR)
                    .fill(iconColor.opacity(isSubOption ? 0.10 : 0.13))
                    .frame(width: iconSize, height: iconSize)
                Image(systemName: icon)
                    .font(.system(size: isSubOption ? 12 : 14, weight: .medium))
                    .foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(isSubOption ? .secondary : .primary)
                Text(description)
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            control()
        }
        .padding(.leading, leadPad).padding(.trailing, 24).padding(.vertical, vPad)
        .background(isSubOption ? Color.primary.opacity(0.025) : Color.clear)
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let icon: String; let iconColor: Color
    let title: String; let description: String
    let isGranted: Bool; let settingsURL: URL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(iconColor.opacity(0.13)).frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium)).foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    statusBadge
                }
                Text(description)
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !isGranted {
                    Button { NSWorkspace.shared.open(settingsURL) } label: {
                        HStack(spacing: 4) {
                            Text("Open System Settings")
                            Image(systemName: "arrow.up.right").font(.system(size: 9))
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.link).padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(isGranted ? Color.green : Color.orange).frame(width: 6, height: 6)
            Text(isGranted ? "Granted" : "Required")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isGranted ? .green : .orange)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background((isGranted ? Color.green : Color.orange).opacity(0.1), in: Capsule())
    }
}

// MARK: - Step Row

private struct StepRow: View {
    let number: Int?
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.13)).frame(width: 28, height: 28)
                if let n = number {
                    Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundColor(.accentColor)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.accentColor)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Link Button

private struct LinkButton: View {
    let label: String; let systemIcon: String
    let color: Color; let url: URL
    @State private var isHovered = false

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 5) {
                Image(systemName: systemIcon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isHovered ? .white : color)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(isHovered ? color : color.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
