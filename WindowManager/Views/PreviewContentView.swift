import SwiftUI

struct PreviewContentView: View {
    let app: NSRunningApplication
    let windows: [WindowInfo]
    let onTap: (WindowInfo) -> Void
    let onMouseEntered: () -> Void
    let onMouseExited: () -> Void

    // Base sizes — scaled by thumbnailScale preference
    private let baseWidth: CGFloat  = 160
    private let baseHeight: CGFloat = 105   // image height only
    private let gridSpacing: CGFloat = 10
    private let maxVisibleRows = 3

    @AppStorage("showPreviewHeader")    private var showPreviewHeader:    Bool   = true
    @AppStorage("showMinimizedWindows") private var showMinimizedWindows: Bool   = true
    @AppStorage("thumbnailScale")       private var thumbnailScale:       Double = 1.0

    private var thumbnailWidth:    CGFloat { baseWidth  * CGFloat(thumbnailScale) }
    // cell = scaled image height + 4 (VStack spacing) + ~15 (title label)
    private var thumbnailCellHeight: CGFloat { baseHeight * CGFloat(thumbnailScale) + 19 }

    /// Respect the "show minimized windows" preference.
    private var displayedWindows: [WindowInfo] {
        showMinimizedWindows ? windows : windows.filter { !$0.isMinimized }
    }

    /// Balanced column count so rows are as even as possible:
    ///  1–4  → single row (1, 2, 3, 4 columns)
    ///  5–8  → two rows  (5→3, 6→3, 7→4, 8→4)
    ///  9+   → three rows, max 4 columns (9→3, 10→4, 11→4, 12→4, 13+→4 with scroll)
    private var columnCount: Int {
        let n = displayedWindows.count
        guard n > 0 else { return 1 }
        if n <= 4 { return n }
        if n <= 8 { return Int(ceil(Double(n) / 2.0)) }
        return min(Int(ceil(Double(n) / 3.0)), 4)
    }

    /// Windows split into rows of `columnCount` each.
    private var rows: [[WindowInfo]] {
        let cols = columnCount
        return stride(from: 0, to: displayedWindows.count, by: cols).map {
            Array(displayedWindows[$0 ..< min($0 + cols, displayedWindows.count)])
        }
    }

    // Panel width exactly fits the columns (no unnecessary whitespace)
    private var panelWidth: CGFloat {
        let cols = CGFloat(columnCount)
        return cols * thumbnailWidth + (cols - 1) * gridSpacing + 24 // 24 = 12 left + 12 right padding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // App header (optional)
            if showPreviewHeader {
                HStack(spacing: 6) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    Text(app.localizedName ?? "Unknown")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Text("\(displayedWindows.count) window\(displayedWindows.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                Divider()
                    .padding(.horizontal, 8)
            }

            if displayedWindows.isEmpty {
                Text("No windows open")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    // VStack(alignment:.center) naturally centers a partial last row
                    // because each HStack is as wide as its content and the VStack
                    // is as wide as the widest (full) row.
                    VStack(alignment: .center, spacing: gridSpacing) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: gridSpacing) {
                                ForEach(row) { window in
                                    ThumbnailView(window: window, onTap: { onTap(window) })
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }
                // Cap at maxVisibleRows tall; scroll vertically if more rows overflow
                .frame(maxHeight: CGFloat(maxVisibleRows) * thumbnailCellHeight
                                  + CGFloat(maxVisibleRows - 1) * gridSpacing
                                  + 10 + 12)  // 10 top + 12 bottom scroll padding
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)
        .frame(width: panelWidth)
        .onHover { inside in
            if inside { onMouseEntered() } else { onMouseExited() }
        }
    }
}
