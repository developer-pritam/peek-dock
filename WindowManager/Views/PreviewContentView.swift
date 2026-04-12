import SwiftUI

struct PreviewContentView: View {
    let app: NSRunningApplication
    let windows: [WindowInfo]
    let onTap: (WindowInfo) -> Void
    let onMouseEntered: () -> Void
    let onMouseExited: () -> Void

    private let thumbnailWidth: CGFloat = 200
    private let thumbnailCellHeight: CGFloat = 149  // 130 image + 4 vstack spacing + ~15 title label
    private let gridSpacing: CGFloat = 12
    private let maxColumns = 4
    private let maxRows = 3

    private var columnCount: Int {
        max(min(windows.count, maxColumns), 1)
    }

    // Panel width exactly fits the columns (no unnecessary whitespace)
    private var panelWidth: CGFloat {
        let cols = CGFloat(columnCount)
        return cols * thumbnailWidth + (cols - 1) * gridSpacing + 24 // 24 = 12 left + 12 right padding
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(thumbnailWidth), spacing: gridSpacing), count: columnCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // App header
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

                Text("\(windows.count) window\(windows.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Divider()
                .padding(.horizontal, 8)

            if windows.isEmpty {
                Text("No windows open")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                        ForEach(windows) { window in
                            ThumbnailView(window: window, onTap: { onTap(window) })
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }
                // Cap at maxRows tall; scroll vertically if more windows overflow
                .frame(maxHeight: CGFloat(maxRows) * thumbnailCellHeight
                                  + CGFloat(maxRows - 1) * gridSpacing
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
