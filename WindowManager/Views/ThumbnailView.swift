import SwiftUI

struct ThumbnailView: View {
    let window: WindowInfo
    let onTap: () -> Void

    @State private var isHovered = false

    private let thumbnailWidth: CGFloat = 200
    private let thumbnailHeight: CGFloat = 130

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                // ── Background ──
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.6))
                    .frame(width: thumbnailWidth, height: thumbnailHeight)

                // ── Screenshot or placeholder ──
                if let cgImage = window.image {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: thumbnailWidth, maxHeight: thumbnailHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: thumbnailWidth, height: thumbnailHeight)
                        Image(systemName: "macwindow")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                    }
                }

                // ── Minimized badge ──
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

                // ── Action buttons (top-left, shown on hover) ──
                if isHovered {
                    HStack(spacing: 5) {
                        WindowActionButton(icon: "xmark", color: Color(red: 1, green: 0.37, blue: 0.34)) {
                            window.close()
                        }
                        WindowActionButton(icon: "minus", color: Color(red: 1, green: 0.74, blue: 0.18)) {
                            window.minimize()
                        }
                        WindowActionButton(icon: "arrow.up.left.and.arrow.down.right", color: Color(red: 0.16, green: 0.78, blue: 0.25)) {
                            window.toggleFullscreen()
                        }
                    }
                    .padding(6)
                    .transition(.opacity.animation(.easeInOut(duration: 0.12)))
                }
            }
            .frame(width: thumbnailWidth, height: thumbnailHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Color.accentColor : Color.clear, lineWidth: 2.5)
            )
            .shadow(radius: isHovered ? 8 : 3)
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)

            // ── Window title ──
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

// MARK: - Action Button

private struct WindowActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 16, height: 16)
                    .shadow(color: color.opacity(0.4), radius: isHovered ? 4 : 0)

                Image(systemName: icon)
                    .font(.system(size: 7, weight: .black))
                    .foregroundColor(Color.black.opacity(isHovered ? 0.7 : 0))
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.15 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
