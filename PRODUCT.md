# Window Manager — Product Overview

## What Is It?

Window Manager is a lightweight macOS utility that lives in your menu bar and adds one focused feature: **hover over any app icon in the Dock and see a live preview of every window that app has open**, then click a thumbnail to jump directly to that window.

It is the macOS equivalent of the Windows taskbar thumbnail previews — something macOS has never shipped natively.

---

## The Problem It Solves

macOS makes switching between windows of the same app harder than it should be. If you have four Finder windows, three terminal tabs, or five browser windows open, your options are:

- **Cmd+Tab** — switches apps, not windows. You still have to hunt for the right window after.
- **Mission Control / Exposé** — requires a gesture or hotkey, zooms out the entire desktop, and shows every window from every app at once. Visually noisy.
- **Window menu** — exists only in apps that implement it, lists windows by title only (no preview), and requires moving the mouse all the way to the menu bar.
- **Click the Dock icon** — raises the app but picks whichever window was last focused. No way to target a specific one.

Window Manager solves this with zero friction: the trigger is something you already do — moving your mouse to the Dock.

---

## How It Works (User Perspective)

### 1. Hover a Dock icon
Move your cursor over any app icon in the Dock. After a brief moment, a floating panel appears just above (or beside, if your Dock is on the left/right) the icon.

```
┌─────────────────────────────────────────────────┐
│  🔵 Finder                              3 windows│
│  ──────────────────────────────────────────────  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │ [thumb]  │  │ [thumb]  │  │ [thumb]  │       │
│  │Downloads │  │ Documents│  │ Projects │       │
│  └──────────┘  └──────────┘  └──────────┘       │
└─────────────────────────────────────────────────┘
                   ▲ Dock icon
```

### 2. See all windows at once
The panel shows every open window for that app as a thumbnail — including windows on other Spaces and minimized windows (marked with a badge). Each thumbnail shows:
- A live screenshot of the window
- The window's title below it

### 3. Click to focus
Click any thumbnail. The panel closes instantly and that exact window comes to the front, regardless of which Space it's on or whether it was minimized.

### 4. Move away to dismiss
Move your cursor away from both the panel and the Dock icon. The panel disappears after a short grace period (250ms), giving you time to move your mouse from the Dock icon up to the panel without it vanishing.

---

## Key Behaviors

| Situation | Behavior |
|---|---|
| App has 1 window | Shows that one window |
| App has multiple windows | Shows all of them side by side |
| Window is minimized | Shows thumbnail with "Minimized" badge |
| Window is on another Space | Still shown; click brings you to that Space |
| App icon is not running | Panel does not appear |
| Dock is on the left | Panel appears to the right of the icon |
| Dock is on the right | Panel appears to the left of the icon |
| Dock is on the bottom | Panel appears above the icon |
| Panel near screen edge | Automatically repositioned to stay on screen |

---

## First Launch Setup

The app requires two permissions, both of which are standard macOS privacy prompts:

1. **Accessibility** — needed to watch the Dock for hover changes. Without this the panel never appears. macOS will prompt you immediately on first launch with a dialog that takes you to System Settings.

2. **Screen Recording** — needed to capture window thumbnails. Without this the panel shows window titles but thumbnails appear blank. macOS prompts for this the first time the app tries to capture a window.

Both permissions can be managed at any time in **System Settings → Privacy & Security**.

---

## What the App Does Not Do

- It does not rearrange, resize, or tile windows (no window management beyond focusing)
- It does not replace Mission Control or Cmd+Tab
- It does not add a Dock icon (it runs entirely from the menu bar)
- It does not run at login automatically (you can add it manually via System Settings → General → Login Items)
- It does not require an internet connection
- It does not collect any data

---

## Menu Bar Icon

The app places a small icon in the macOS menu bar (top-right area). Clicking it shows a simple menu with a Quit option. There are no settings yet — the app is intentionally simple.

---

## Inspiration

The direct inspiration is the Windows taskbar thumbnail previews introduced in Windows Vista/7, and the open-source app [DockDoor](https://github.com/ejbills/DockDoor) which pioneered this approach on macOS. Window Manager is a clean-room implementation of the same core idea.
