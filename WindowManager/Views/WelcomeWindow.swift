import SwiftUI
import ApplicationServices
import ServiceManagement

extension Notification.Name {
    static let peekDockStatusBarVisibilityChanged = Notification.Name("PeekDockStatusBarVisibilityChanged")
}

// ── Customise these before shipping ──────────────────────────────────────────
private let kPortfolioURL = URL(string: "https://developerpritam.in")!
private let kDonationURL  = URL(string: "https://developerpritam.in/donate")!
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Window Controller

final class WelcomeWindowController: NSWindowController {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 0),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "PeekDock"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false

        let view = WelcomeView { window.close() }
        window.contentView = NSHostingView(rootView: view)
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - SwiftUI View

struct WelcomeView: View {
    let close: () -> Void

    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @AppStorage("hideStatusBarIcon") private var hideStatusBarIcon = false

    // Re-check permissions every second so the UI auto-updates after the user
    // returns from System Settings without needing to click Refresh.
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            permissionsSection
            Divider()
            preferencesSection
            Divider()
            howToUseSection
            Divider()
            footerSection
        }
        .frame(width: 480)
        .onAppear { refreshPermissions() }
        .onReceive(timer) { _ in refreshPermissions() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("PeekDock")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("v\(appVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                Text("Instant window previews, right from your Dock")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Permissions")

            PermissionRow(
                icon: "accessibility",
                iconColor: .blue,
                title: "Accessibility",
                description: "Lets the app watch the Dock for hover events and detect which app icon your cursor is over. Without this, the preview panel cannot appear.",
                isGranted: accessibilityGranted,
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )

            Divider().padding(.leading, 54)

            PermissionRow(
                icon: "video.fill",
                iconColor: .purple,
                title: "Screen Recording",
                description: "Captures live thumbnail images of each open window. Only used to render previews — no content is stored or transmitted.",
                isGranted: screenRecordingGranted,
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            )
        }
        .padding(.bottom, 4)
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Preferences")

            // Launch at Login
            PreferenceRow(
                icon: "arrow.circlepath",
                iconColor: .green,
                title: "Launch at Login",
                description: "Automatically start PeekDock when you log in to your Mac."
            ) {
                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            // Roll back the toggle if the system call failed
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                        }
                    }
            }

            Divider().padding(.leading, 54)

            // Hide menu bar icon
            PreferenceRow(
                icon: "menubar.rectangle",
                iconColor: .secondary,
                title: "Hide menu bar icon",
                description: "PeekDock still runs in the background. Reopen this window by relaunching the app."
            ) {
                Toggle("", isOn: $hideStatusBarIcon)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: hideStatusBarIcon) { _ in
                        NotificationCenter.default.post(name: .peekDockStatusBarVisibilityChanged, object: nil)
                    }
            }
            .padding(.bottom, 4)
        }
    }

    // MARK: - How to Use

    private var howToUseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("How to Use")

            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, text: "Hover any app icon in your **Dock** — even ones with multiple windows open")
                StepRow(number: 2, text: "A **preview panel** pops up showing all windows for that app as live thumbnails")
                StepRow(number: 3, text: "**Click** any thumbnail to instantly switch to that window")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 10) {
            LinkButton(
                label: "Buy me a coffee",
                systemIcon: "cup.and.saucer.fill",
                color: .orange,
                url: kDonationURL
            )
            LinkButton(
                label: "Portfolio",
                systemIcon: "globe",
                color: .blue,
                url: kPortfolioURL
            )

            Spacer()

            if !accessibilityGranted || !screenRecordingGranted {
                Text("Permissions required")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Button("Done") { close() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.8)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 10)
    }

    private func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Preference Row

private struct PreferenceRow<Control: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            control()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isGranted: Bool
    let settingsURL: URL

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(iconColor)
            }

            // Text + action
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))

                    statusBadge
                }

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !isGranted {
                    Button {
                        NSWorkspace.shared.open(settingsURL)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Open System Settings")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.link)
                    .padding(.top, 2)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isGranted ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(isGranted ? "Granted" : "Required")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isGranted ? .green : .orange)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((isGranted ? Color.green : Color.orange).opacity(0.1), in: Capsule())
    }
}

// MARK: - Step Row

private struct StepRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 24, height: 24)
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.accentColor)
            }
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Link Button

private struct LinkButton: View {
    let label: String
    let systemIcon: String
    let color: Color
    let url: URL

    @State private var isHovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemIcon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isHovered ? .white : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? color : color.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
