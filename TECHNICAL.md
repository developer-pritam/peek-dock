# Window Manager — Technical Documentation

## Overview

Window Manager is a native macOS application built in Swift. It uses a combination of public macOS frameworks and several private/undocumented APIs to implement Dock hover detection, window enumeration, screenshot capture, and window focusing — none of which Apple provides a clean public API for.

The project targets **macOS 14.0+** and is **not App Sandboxed**, which is a hard requirement: the private APIs and screen capture entitlements needed are not available inside the sandbox.

---

## Project Structure

```
WindowManager/
├── App/
│   ├── main.swift                        Entry point — bootstraps NSApplication
│   ├── AppDelegate.swift                 App lifecycle, permissions, wires components
│   └── Info.plist / .entitlements        LSUIElement=YES, no sandbox
├── Utilities/
│   ├── PrivateApis.swift                 All private/undocumented API declarations
│   ├── DockObserver.swift                Dock hover detection via AXObserver
│   └── DockUtils.swift                  Dock position via CoreDock private API
├── Extensions/
│   └── AXUIElement+Helpers.swift        Convenience wrappers around AX attribute calls
├── WindowManagement/
│   ├── WindowInfo.swift                  Window data model + bringToFront()
│   └── WindowUtil.swift                  Window enumeration, screenshot capture, cache
└── Views/
    ├── PreviewPanelCoordinator.swift     NSPanel subclass — lifecycle and positioning
    ├── PreviewContentView.swift          SwiftUI root view — app header + thumbnail row
    └── ThumbnailView.swift               SwiftUI single thumbnail cell
```

---

## Complete Data Flow

```
1. DockObserver sets up AXObserver on com.apple.dock process
        │
        │  (user hovers a Dock icon)
        ▼
2. kAXSelectedChildrenChangedNotification fires
        │
        ▼
3. DockObserver.processSelectedDockItemChanged()
   ├── getHoveredAppDockItem()  →  reads kAXSelectedChildrenAttribute on Dock list
   ├── reads kAXURLAttribute    →  resolves bundle URL → NSRunningApplication
   └── reads kAXPositionAttribute + kAXSizeAttribute  →  dockIconRect (CGRect)
        │
        ▼
4. PreviewPanelCoordinator.showPreview(app:dockIconRect:mouseLocation:)
   ├── render immediately with WindowCache.shared.read(pid:)  →  may be empty on first hover
   ├── calculatePosition()  →  positions panel above/beside Dock icon
   └── orderFront(nil)  →  panel appears
        │
        ▼  (Task.detached — off main thread)
5. WindowUtil.getActiveWindows(of: app)
   ├── SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
   │       filters to app's windows where windowLayer == 0
   │       ├── for each SCWindow: captureAndCacheWindow()
   │       │       ├── captureWithSCK()  →  SCScreenshotManager.captureImage()  (primary)
   │       │       └── cgsCaptureWindowImage()  →  CGSHWCaptureWindowList()    (fallback)
   │       └── stores WindowInfo { id, image, axElement, frame, ... } in WindowCache
   └── discoverAXWindows()  →  finds minimized/hidden/other-space windows via AX brute-force
        │
        ▼  (back on MainActor)
6. PreviewPanelCoordinator re-renders panel with fresh [WindowInfo]
        │
        │  (user clicks thumbnail)
        ▼
7. WindowInfo.bringToFront()
   ├── GetProcessForPID()               →  ProcessSerialNumber from Carbon
   ├── _SLPSSetFrontProcessWithOptions  →  SkyLight.framework (dlopen'd)
   └── AXUIElement.performAction(kAXRaiseAction)
        │
        ▼
8. PreviewPanelCoordinator.hidePanel()
```

---

## Component Deep Dive

### `DockObserver` — Dock Hover Detection

The Dock is a separate process (`com.apple.dock`). There is no public API to detect which icon the user is hovering. The approach uses macOS Accessibility (AX) framework notifications.

**Setup:**
```swift
// 1. Get Dock's AX element
let dockElement = AXUIElementCreateApplication(dockPID)

// 2. Find the list element (the container of all Dock icons)
let axList = dockElement.children().first { $0.role() == kAXListRole }

// 3. Subscribe to selection changes — fires every time hover changes
AXObserverCreate(dockPID, callbackFn, &observer)
AXObserverAddNotification(observer, axList, kAXSelectedChildrenChangedNotification, nil)
CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .commonModes)
```

The `kAXSelectedChildrenChangedNotification` on the Dock's list fires every time the user moves their cursor from one icon to another. This is the hook the entire feature is built on.

**Identifying the hovered icon:**
```swift
// Read which child is currently "selected" (hovered)
AXUIElementCopyAttributeValue(dockList, kAXSelectedChildrenAttribute, &selectedChildren)
let hoveredItem = (selectedChildren as? [AXUIElement])?.first

// Filter to only actual app icons (not Trash, folders, separators)
guard hoveredItem.subrole() == "AXApplicationDockItem" else { return }

// Get the app's bundle URL from the AX element
let appURL = hoveredItem.attribute(kAXURLAttribute, NSURL.self)
let bundleID = Bundle(url: appURL).bundleIdentifier
let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
```

**Health check:** A `Timer` fires every 5 seconds to verify the observer is still alive. The Dock process can restart (rare) or its AX tree can become invalid, which silently stops notifications. If detected, the observer is torn down and rebuilt.

**Why not mouse polling?** Polling `NSEvent.mouseLocation` every N milliseconds would work but wastes CPU, introduces latency, and has no reliable way to know when the cursor is over a specific Dock icon. The AX notification approach is event-driven and zero-cost when idle.

---

### `DockUtils` — Dock Position Detection

The Dock can be positioned on the bottom, left, or right of the screen. Panel placement depends on knowing which side. macOS provides no public API for this. We use a CoreDock private function:

```swift
@_silgen_name("CoreDockGetOrientationAndPinning")
func CoreDockGetOrientationAndPinning(
    _ outOrientation: UnsafeMutablePointer<Int32>,
    _ outPinning: UnsafeMutablePointer<Int32>
)
// Returns: 1=top, 2=bottom, 3=left, 4=right
```

`@_silgen_name` is a Swift compiler directive that tells the linker to resolve this function by name from any loaded framework — in this case, `Dock.framework` which is automatically loaded as part of the AppKit stack.

---

### `PrivateApis.swift` — Private API Declarations

All undocumented APIs are declared in one file for clarity. Three categories:

**1. CoreGraphics private functions (`@_silgen_name`)**
```swift
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> CGSConnectionID
@_silgen_name("CGSHWCaptureWindowList") func CGSHWCaptureWindowList(...) -> CFArray?
@_silgen_name("CGSCopySpacesForWindows") func CGSCopySpacesForWindows(...) -> CFArray?
@_silgen_name("_AXUIElementGetWindow") func _AXUIElementGetWindow(_ el: AXUIElement, _ wid: inout CGWindowID) -> AXError
@_silgen_name("_AXUIElementCreateWithRemoteToken") func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?
```

**2. CoreDock (`@_silgen_name`)**
```swift
@_silgen_name("CoreDockGetOrientationAndPinning") func CoreDockGetOrientationAndPinning(...)
@_silgen_name("CoreDockSetAutoHideEnabled") func CoreDockSetAutoHideEnabled(_ flag: Bool)
```

**3. SkyLight.framework (`dlopen` / `dlsym`)**

SkyLight is a private framework that cannot be linked at compile time (it's not in the SDK). It must be loaded at runtime:

```swift
let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
let symbol = dlsym(handle, "_SLPSSetFrontProcessWithOptions")
setFrontProcessPtr = unsafeBitCast(symbol, to: SLPSSetFrontProcessWithOptionsType.self)
```

The function `_SLPSSetFrontProcessWithOptions` takes a `ProcessSerialNumber` (a legacy Carbon type), a target window ID, and a mode flag. It is the only reliable way to bring a specific window to front across all apps and spaces.

---

### `WindowUtil` — Window Enumeration and Capture

**Window enumeration** uses ScreenCaptureKit's `SCShareableContent`:
```swift
let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
let appWindows = content.windows.filter {
    $0.owningApplication?.processID == pid && $0.windowLayer == 0
}
```

`windowLayer == 0` filters out system UI elements (Dock = layer 8, menu bar = layer 25, popovers = higher) and returns only real application windows.

**Two-path window discovery:**

- **Path 1 — SCK (on-screen windows):** `SCShareableContent` returns all visible windows on the current Space.
- **Path 2 — AX brute-force (off-screen windows):** Minimized windows and windows on other Spaces are not returned by SCK. For these, the Accessibility API is used.

The brute-force AX approach crafts fake `AXUIElement` tokens and iterates IDs 0–999:
```swift
// Craft a 20-byte token: [PID(4)] [padding(4)] [magic "coco"(4)] [axID(8)]
var token = Data(count: 20)
token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636F_636F)) { Data($0) })
for axId: UInt64 in 0..<1000 {
    token.replaceSubrange(12..<20, with: withUnsafeBytes(of: axId) { Data($0) })
    if let el = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue(),
       [kAXStandardWindowSubrole, kAXDialogSubrole].contains(try? el.subrole()) {
        results.append(el)
    }
}
```

The magic value `0x636F_636F` is ASCII for "coco" (short for Cocoa), which is baked into the AX subsystem's token format.

**Window capture** uses two methods in priority order:

1. **`SCScreenshotManager.captureImage(contentFilter:configuration:)`** (macOS 14, public API)
   - Creates an `SCContentFilter(desktopIndependentWindow: scWindow)` — targets exactly one window
   - Scales output to thumbnail size to save memory and capture time
   - Automatically triggers the Screen Recording permission dialog if not yet granted
   - This is the primary method for on-screen windows

2. **`CGSHWCaptureWindowList`** (CoreGraphics private API, fallback)
   - Faster for single captures; works for minimized windows in some cases
   - Requires Screen Recording permission to be pre-granted (does not prompt)
   - Used as fallback when SCK fails, and as primary for AX-discovered (off-screen) windows

```swift
// Primary: SCScreenshotManager
let filter = SCContentFilter(desktopIndependentWindow: scWindow)
let config = SCStreamConfiguration()
config.width = Int(scWindow.frame.width * scale * displayScale)
config.height = Int(scWindow.frame.height * scale * displayScale)
config.captureResolution = .best
let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

// Fallback: CGS
var wid = UInt32(windowID)
let images = CGSHWCaptureWindowList(CGSMainConnectionID(), &wid, 1,
    [.ignoreGlobalClipShape, .bestResolution, .fullSize]) as? [CGImage]
```

The `.fullSize` option on CGS is required for correct output when Stage Manager is active — without it, Stage Manager can clip or skew the captured image.

**Concurrency:** Captures run in a `TaskGroup` with a maximum of 4 concurrent captures. This prevents overloading `SCScreenshotManager`, which can return errors or corrupt data under heavy parallel load.

**Caching:** Results are stored in `WindowCache` (a thread-safe `[pid_t: [WindowInfo]]` dictionary protected by `NSLock`). Images are valid for 30 seconds. On subsequent hovers of the same app, cached data is shown immediately while fresh data loads in the background.

---

### `AXUIElement+Helpers` — AX Convenience Layer

Direct AX calls are verbose and error-prone. All attribute reading is wrapped:

```swift
// Raw AX call:
var value: AnyObject?
AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value)
// then extract CGPoint from AXValue...

// Wrapped:
let position = try element.position()  // returns CGPoint?
```

`axCallWhichCanThrow` centralises error mapping:
- `.success` → return value
- `.cannotComplete` → `throw AxError.runtimeError` (app is unresponsive; caller can retry)
- anything else → return `nil` (attribute not applicable for this element)

`AXUIElementSetMessagingTimeout` is set to 1.0 seconds on all app-level AX elements to prevent hangs when an app is unresponsive.

---

### `PreviewPanelCoordinator` — NSPanel Management

The panel is an `NSPanel` subclass (not `NSWindow`) with specific style flags:

```swift
styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless]
level = .statusBar
collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
becomesKeyOnlyIfNeeded = true
hidesOnDeactivate = false
```

Key flags explained:
- **`.nonactivatingPanel`** — the panel receives clicks but does NOT steal keyboard focus from whatever app the user is currently using. Without this, hovering the Dock would deactivate the frontmost app before any click registers.
- **`.statusBar` level** — appears above regular windows and the Dock itself
- **`.canJoinAllSpaces`** — the panel is visible on whichever Space the user is on, since windows from other Spaces can also be shown
- **`hidesOnDeactivate = false`** — prevents the panel from vanishing when the user moves the cursor to an app window

**Panel positioning:**

The Dock icon rect (from AX) uses Quartz coordinates (origin at top-left of primary screen). AppKit window frames use a flipped coordinate system (origin at bottom-left). Conversion is required:

```swift
// Quartz (AX) → AppKit (NSWindow)
let flippedY = screen.frame.height - axPoint.y
```

Placement relative to Dock position:
- **Bottom Dock:** panel appears above the icon, horizontally centered on icon midX
- **Left Dock:** panel appears to the right of the icon, vertically centered on icon midY
- **Right Dock:** panel appears to the left of the icon, vertically centered on icon midY

The panel is clamped to screen bounds with an 8pt margin to prevent it from going off-screen for icons at the edges of the Dock.

**Dismiss logic — grace period:**
```
User cursor leaves Dock icon → kAXSelectedChildrenChangedNotification fires (hoveredItem = nil)
    → scheduleHide() starts a 250ms timer
    → if cursor enters panel within 250ms → timer cancelled, panel stays
    → if 250ms elapses and cursor is not in panel → hidePanel()
```

This grace period is essential. Without it, any slight mouse movement while aiming at the panel would dismiss it.

---

### `WindowInfo` — Window Model + Focusing

`WindowInfo` is a value type (`struct`) carrying all data about one window:

| Field | Type | Source |
|---|---|---|
| `id` | `CGWindowID` | From SCWindow or `_AXUIElementGetWindow` |
| `app` | `NSRunningApplication` | From SCWindow.owningApplication |
| `windowName` | `String?` | AX `kAXTitleAttribute` or SCWindow.title |
| `image` | `CGImage?` | From SCScreenshotManager or CGS |
| `axElement` | `AXUIElement` | Matched by CGWindowID or frame position |
| `appAxElement` | `AXUIElement` | `AXUIElementCreateApplication(pid)` |
| `frame` | `CGRect` | From SCWindow.frame or AX position+size |
| `isMinimized` | `Bool` | AX `kAXMinimizedAttribute` |
| `isHidden` | `Bool` | `NSRunningApplication.isHidden` |

**`bringToFront()`** uses three APIs in sequence:

```swift
// 1. ProcessSerialNumber — legacy Carbon identifier (still required for SkyLight)
var psn = ProcessSerialNumber()
GetProcessForPID(app.processIdentifier, &psn)

// 2. SkyLight — brings the process to front at the window server level
_SLPSSetFrontProcessWithOptions(&psn, UInt32(id), SLPSMode.userGenerated.rawValue)

// 3. AX — raises and focuses the specific window within the app
axElement.performAction(kAXRaiseAction)
axElement.setAttribute(kAXMainWindowAttribute, true)
```

The combination of all three is necessary: SkyLight alone brings the app to front but may not pick the right window; AX alone works within the app but may not activate the app at the window server level if it wasn't already frontmost.

Retries up to 3 times with 50ms delays, since `kAXRaiseAction` can fail transiently when an app is busy.

---

### Coordinate Systems

macOS has three different coordinate systems, all in use simultaneously:

| System | Origin | Used by |
|---|---|---|
| Quartz / CGEvent | Top-left of primary screen | CGEvent, AX position attributes, SCWindow.frame |
| AppKit / NSWindow | Bottom-left of primary screen | NSWindow.frame, NSScreen.frame, NSEvent.mouseLocation |
| Screen-relative | Top-left of each screen | Some SCKit APIs |

The conversion between Quartz and AppKit for a point on a non-primary screen requires knowing the screen's offset from the primary screen's top-left, which is non-trivial. `DockObserver.nsPointFromCGPoint` and `cgPointFromNSPoint` implement this correctly for multi-monitor setups.

---

### Permission Strategy

| Permission | API Used | When Prompted | Impact if Denied |
|---|---|---|---|
| Accessibility | `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` | Immediately on first launch | Panel never appears (Dock hover not detected) |
| Screen Recording | Triggered by first `SCShareableContent` call | On first Dock hover | Panel appears but all thumbnails are blank |

The Screen Recording permission is intentionally not gated behind `CGPreflightScreenCaptureAccess()`. That function returns `false` even after the user has granted permission in the current session until the app is relaunched — making it an unreliable guard. Instead, `SCShareableContent` is called unconditionally and handles the permission dialog itself.

---

### Build Configuration

```yaml
# project.yml (xcodegen)
MACOSX_DEPLOYMENT_TARGET: "14.0"      # Required for SCScreenshotManager
SWIFT_VERSION: "5.10"
ENABLE_APP_SANDBOX: NO                 # Hard requirement — private APIs
CODE_SIGN_IDENTITY: "-"               # Sign to Run Locally (no Apple Developer account needed)
```

Linked frameworks:
- `ScreenCaptureKit` — window enumeration + SCScreenshotManager
- `ApplicationServices` — AX APIs
- `Carbon` — Carbon event types (ProcessSerialNumber, GetProcessForPID)

SkyLight and CoreDock are not linked at compile time — they are loaded dynamically at runtime via `@_silgen_name` (for symbols already in the process's address space via AppKit) and `dlopen`/`dlsym` (for SkyLight, which is not auto-loaded).

To regenerate the Xcode project after adding or removing files:
```bash
xcodegen generate   # reads project.yml, writes WindowManager.xcodeproj
```

To build from command line:
```bash
xcodebuild -project WindowManager.xcodeproj -scheme WindowManager -configuration Debug build
```
