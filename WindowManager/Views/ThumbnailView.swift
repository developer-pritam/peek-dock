import SwiftUI

struct ThumbnailView: View {
    let window: WindowInfo
    let onTap: () -> Void

    @State private var isHovered = false

    private let thumbnailWidth: CGFloat = 200
    private let thumbnailHeight: CGFloat = 130

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.6))
                    .frame(width: thumbnailWidth, height: thumbnailHeight)

                if let cgImage = window.image {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: thumbnailWidth, maxHeight: thumbnailHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    // Placeholder while loading
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: thumbnailWidth, height: thumbnailHeight)
                        Image(systemName: "macwindow")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                    }
                }

                // Minimized badge
                if window.isMinimized {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Label("Minimized", systemImage: "minus.circle.fill")
                                .font(.caption2)
                                .padding(4)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(6)
                        }
                    }
                    .frame(width: thumbnailWidth, height: thumbnailHeight)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Color.accentColor : Color.clear, lineWidth: 2.5)
            )
            .shadow(radius: isHovered ? 8 : 3)
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)

            // Window title
            Text(window.windowName ?? "Untitled")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: thumbnailWidth)
        }
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
        .help(window.windowName ?? "Untitled")
    }
}
