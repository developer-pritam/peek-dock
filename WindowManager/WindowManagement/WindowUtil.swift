import ApplicationServices
import Cocoa
import ScreenCaptureKit

// MARK: - Simple Window Cache

final class WindowCache {
    static let shared = WindowCache()
    private var cache: [pid_t: [WindowInfo]] = [:]
    private let lock = NSLock()

    func read(pid: pid_t) -> [WindowInfo] {
        lock.lock(); defer { lock.unlock() }
        return cache[pid] ?? []
    }

    func write(pid: pid_t, windows: [WindowInfo]) {
        lock.lock(); defer { lock.unlock() }
        cache[pid] = windows
    }

    func clear(pid: pid_t) {
        lock.lock(); defer { lock.unlock() }
        cache.removeValue(forKey: pid)
    }
}

// MARK: - Window Utilities

enum WindowUtil {
    private static let captureError = NSError(domain: "WindowUtil", code: -1)
    private static let cacheLifespan: TimeInterval = 30.0

    // MARK: - Fetch Active Windows for an App

    static func getActiveWindows(of app: NSRunningApplication) async throws -> [WindowInfo] {
        let pid = app.processIdentifier
        var sckWindowIDs = Set<CGWindowID>()

        // SCShareableContent auto-triggers Screen Recording permission dialog on first call.
        // Do NOT gate this on CGPreflightScreenCaptureAccess() — that returns false until
        // the user has explicitly visited System Settings, causing images to never load.
        if let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) {
            let appWindows = content.windows.filter {
                $0.owningApplication?.processID == pid && $0.windowLayer == 0
            }
            sckWindowIDs = Set(appWindows.map(\.windowID))

            // Capture thumbnails concurrently (max 4 at a time)
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                for window in appWindows {
                    if inFlight >= 4 {
                        await group.next()
                        inFlight -= 1
                    }
                    group.addTask {
                        await captureAndCacheWindow(scWindow: window, app: app)
                    }
                    inFlight += 1
                }
                // Drain remaining tasks
                for await _ in group {}
            }
        }

        // Also discover windows via AX (minimized, hidden, other-space windows)
        await discoverAXWindows(app: app, excludeWindowIDs: sckWindowIDs)

        return WindowCache.shared.read(pid: pid)
    }

    // MARK: - SCK Window Capture (per-window SCScreenshotManager)

    private static func captureAndCacheWindow(scWindow: SCWindow, app: NSRunningApplication) async {
        let pid = app.processIdentifier
        let windowID = scWindow.windowID
        let appAxElement = AXUIElementCreateApplication(pid)

        // Skip if we have a fresh cached image
        let cached = WindowCache.shared.read(pid: pid).first(where: { $0.id == windowID })
        if let cached, cached.image != nil,
           Date().timeIntervalSince(cached.imageCapturedTime) < cacheLifespan {
            return
        }

        // Get matching AX element for this window
        let axWindows = AXUIElement.allWindows(pid, appElement: appAxElement)
        let axElement = findAXWindow(matching: scWindow, in: axWindows) ?? appAxElement

        let isMinimized = (try? axElement.isMinimized()) ?? false
        let windowName = (try? axElement.title()) ?? scWindow.title

        // Capture via SCScreenshotManager (macOS 14+) — triggers permission dialog automatically
        let image = await captureWithSCK(scWindow: scWindow)
            ?? (try? cgsCaptureWindowImage(windowID: windowID))  // fallback to CGS private API

        let info = WindowInfo(
            id: windowID,
            app: app,
            windowName: windowName,
            image: image,
            axElement: axElement,
            appAxElement: appAxElement,
            frame: scWindow.frame,
            isMinimized: isMinimized,
            isHidden: app.isHidden
        )

        var existing = WindowCache.shared.read(pid: pid)
        if let idx = existing.firstIndex(where: { $0.id == windowID }) {
            existing[idx] = info
        } else {
            existing.append(info)
        }
        WindowCache.shared.write(pid: pid, windows: existing)
    }

    /// Capture a window screenshot using ScreenCaptureKit (macOS 14+).
    /// This is the primary capture method — it auto-triggers the Screen Recording permission dialog.
    static func captureWithSCK(scWindow: SCWindow) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()

        // Scale down to thumbnail size for efficiency
        let targetHeight: CGFloat = 300
        let scale = min(targetHeight / max(scWindow.frame.height, 1), 1.0)
        let displayScale = NSScreen.main?.backingScaleFactor ?? 2.0
        config.width = max(Int(scWindow.frame.width * scale * displayScale), 1)
        config.height = max(Int(scWindow.frame.height * scale * displayScale), 1)
        config.showsCursor = false
        config.captureResolution = .best

        return try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    /// Fallback: capture via private CGSHWCaptureWindowList (faster but needs pre-granted permission).
    static func cgsCaptureWindowImage(windowID: CGWindowID) throws -> CGImage {
        var windowIDUInt32 = UInt32(windowID)
        let cid = CGSMainConnectionID()
        guard let captured = CGSHWCaptureWindowList(
            cid, &windowIDUInt32, 1,
            [.ignoreGlobalClipShape, .bestResolution, .fullSize]
        ) as? [CGImage], let image = captured.first
        else { throw captureError }
        return image
    }

    // MARK: - AX Window Discovery (minimized, hidden, other-space windows)

    private static func discoverAXWindows(app: NSRunningApplication, excludeWindowIDs: Set<CGWindowID>) async {
        let pid = app.processIdentifier
        let appAxElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appAxElement, 1.0)
        let axWindows = AXUIElement.allWindows(pid, appElement: appAxElement)

        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            for axWin in axWindows {
                guard let windowID = try? axWin.cgWindowId(),
                      !excludeWindowIDs.contains(windowID)
                else { continue }

                if inFlight >= 4 { await group.next(); inFlight -= 1 }
                group.addTask {
                    let isMinimized = (try? axWin.isMinimized()) ?? false
                    let windowName = try? axWin.title()
                    let pos = try? axWin.position()
                    let sz = try? axWin.size()
                    let frame = (pos != nil && sz != nil)
                        ? CGRect(origin: pos!, size: sz!) : .zero

                    // Try to capture even minimized windows via CGS
                    let image = try? cgsCaptureWindowImage(windowID: windowID)

                    let info = WindowInfo(
                        id: windowID,
                        app: app,
                        windowName: windowName,
                        image: image,
                        axElement: axWin,
                        appAxElement: appAxElement,
                        frame: frame,
                        isMinimized: isMinimized,
                        isHidden: app.isHidden
                    )

                    var existing = WindowCache.shared.read(pid: app.processIdentifier)
                    if !existing.contains(where: { $0.id == windowID }) {
                        existing.append(info)
                        WindowCache.shared.write(pid: app.processIdentifier, windows: existing)
                    }
                }
                inFlight += 1
            }
            for await _ in group {}
        }
    }

    // MARK: - AX Window Matching

    static func findAXWindow(matching scWindow: SCWindow, in axWindows: [AXUIElement]) -> AXUIElement? {
        // Primary: match by CGWindowID
        for axWin in axWindows {
            if let axID = try? axWin.cgWindowId(), axID == scWindow.windowID {
                return axWin
            }
        }
        // Fallback: match by frame origin (within 2pt tolerance)
        for axWin in axWindows {
            if let pos = try? axWin.position(), let sz = try? axWin.size() {
                let axFrame = CGRect(origin: pos, size: sz)
                if abs(axFrame.origin.x - scWindow.frame.origin.x) <= 2,
                   abs(axFrame.origin.y - scWindow.frame.origin.y) <= 2 {
                    return axWin
                }
            }
        }
        return nil
    }

    // MARK: - Window Focus (called from WindowInfo.bringToFront)

    static func makeKeyWindow(_ psn: inout ProcessSerialNumber, windowID: CGWindowID) {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xF8
        bytes[0x08] = 0x01
        bytes[0x3a] = 0x10
        withUnsafeMutableBytes(of: &bytes) { ptr in
            ptr.storeBytes(of: UInt32(windowID), toByteOffset: 0x3c, as: UInt32.self)
        }
        bytes.withUnsafeMutableBytes { rawPtr in
            _ = SLPSPostEventRecordTo(&psn, rawPtr.baseAddress!.assumingMemoryBound(to: UInt8.self))
        }
    }
}

// MARK: - SLPSPostEventRecordTo (SkyLight private API)

private typealias SLPSPostEventRecordToFn = @convention(c) (
    UnsafeMutableRawPointer,
    UnsafeMutablePointer<UInt8>
) -> CGError

private var _postEventPtr: SLPSPostEventRecordToFn?

func SLPSPostEventRecordTo(_ psn: inout ProcessSerialNumber, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError {
    if _postEventPtr == nil {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        if let handle = dlopen(path, RTLD_LAZY),
           let sym = dlsym(handle, "SLPSPostEventRecordTo") {
            _postEventPtr = unsafeBitCast(sym, to: SLPSPostEventRecordToFn.self)
        }
    }
    guard let fn = _postEventPtr else { return CGError(rawValue: -1)! }
    return fn(&psn, bytes)
}
