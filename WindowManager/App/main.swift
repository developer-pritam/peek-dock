import Cocoa

// AppDelegate is @MainActor — initialize on the main thread
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
