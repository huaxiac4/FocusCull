import AppKit
import FocusCullCore
import SwiftUI

struct ZoomablePhotoContent: View {
    let image: NSImage
    let photo: PhotoItem
    let showFocusBox: Bool
    let hoverMagnification: Double
    @Binding var zoomScale: CGFloat
    @Binding var panOffset: CGSize

    @State private var isHovering = false
    @State private var dragStart = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let fitted = fittedRect(in: size)
            let effectiveScale = zoomScale * (isHovering ? hoverMagnification : 1)
            let limitX = max(0, (fitted.width * effectiveScale - size.width) / 2 + 30)
            let limitY = max(0, (fitted.height * effectiveScale - size.height) / 2 + 30)

            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fitted.width, height: fitted.height)
                    .offset(x: fitted.minX, y: fitted.minY)

                if showFocusBox, let rect = photo.analysis.focusRect {
                    FocusBoxView()
                        .frame(
                            width: max(24, fitted.width * rect.width),
                            height: max(24, fitted.height * rect.height)
                        )
                        .offset(
                            x: fitted.minX + fitted.width * rect.x,
                            y: fitted.minY + fitted.height * rect.y
                        )
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .scaleEffect(effectiveScale, anchor: .center)
            .offset(panOffset)
            .clipped()
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard zoomScale > 1.01 else { return }
                        panOffset = CGSize(
                            width: min(limitX, max(-limitX, dragStart.width + value.translation.width)),
                            height: min(limitY, max(-limitY, dragStart.height + value.translation.height))
                        )
                    }
                    .onEnded { _ in
                        dragStart = panOffset
                    }
            )
            .onChange(of: photo.id) {
                panOffset = .zero
                dragStart = .zero
            }
            .onChange(of: zoomScale) {
                if zoomScale <= 1.001 {
                    panOffset = .zero
                    dragStart = .zero
                }
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.84), value: isHovering)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: zoomScale)
    }

    private func fittedRect(in size: CGSize) -> CGRect {
        let sourceWidth = image.size.width > 0
            ? image.size.width
            : CGFloat(max(1, photo.analysis.pixelWidth))
        let sourceHeight = image.size.height > 0
            ? image.size.height
            : CGFloat(max(1, photo.analysis.pixelHeight))
        let imageWidth = max(1, sourceWidth)
        let imageHeight = max(1, sourceHeight)
        let padding: CGFloat = 18
        let availableWidth = max(1, size.width - padding * 2)
        let availableHeight = max(1, size.height - padding * 2)
        let scale = min(availableWidth / imageWidth, availableHeight / imageHeight)
        let width = imageWidth * scale
        let height = imageHeight * scale
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }
}

private struct FocusBoxView: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    Theme.accent,
                    style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                )
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.accent.opacity(0.07))
                )
                .shadow(color: Theme.accent.opacity(0.35), radius: 7)

            Text("合焦")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.82))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.accent, in: Capsule())
                .padding(5)
        }
        .allowsHitTesting(false)
    }
}
