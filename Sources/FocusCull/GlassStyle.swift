import SwiftUI

struct LiquidBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Theme.canvas

            LinearGradient(
                colors: [
                    Theme.accent.opacity(colorScheme == .dark ? 0.12 : 0.18),
                    Color.clear,
                    Theme.secondaryAccent.opacity(colorScheme == .dark ? 0.09 : 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Theme.accent.opacity(colorScheme == .dark ? 0.18 : 0.22))
                .frame(width: 620, height: 620)
                .blur(radius: 170)
                .offset(x: -430, y: -320)

            Circle()
                .fill(Theme.secondaryAccent.opacity(colorScheme == .dark ? 0.13 : 0.16))
                .frame(width: 560, height: 560)
                .blur(radius: 180)
                .offset(x: 470, y: 360)

            LinearGradient(
                colors: [.white.opacity(colorScheme == .dark ? 0.02 : 0.18), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

private struct GlassPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat
    var tint: Color?
    var interactive: Bool
    var shadow: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
                .overlay(specularEdge)
                .shadow(color: shadowColor, radius: shadow ? 18 : 0, y: shadow ? 8 : 0)
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            LinearGradient(
                                colors: [
                                    .white.opacity(colorScheme == .dark ? 0.07 : 0.22),
                                    .clear,
                                    .white.opacity(0.025)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        }
                }
                .overlay(specularEdge)
                .shadow(color: shadowColor, radius: shadow ? 16 : 0, y: shadow ? 7 : 0)
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        var value = Glass.regular
        if let tint {
            value = value.tint(tint)
        }
        if interactive {
            value = value.interactive()
        }
        return value
    }

    private var specularEdge: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(colorScheme == .dark ? 0.34 : 0.55),
                        .white.opacity(0.04),
                        .white.opacity(0.015),
                        .white.opacity(colorScheme == .dark ? 0.18 : 0.30)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
            )
            .allowsHitTesting(false)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.32) : .black.opacity(0.14)
    }
}

extension View {
    func glassPanel(
        cornerRadius: CGFloat = 20,
        tint: Color? = nil,
        interactive: Bool = false,
        shadow: Bool = true
    ) -> some View {
        modifier(
            GlassPanelModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                interactive: interactive,
                shadow: shadow
            )
        )
    }
}
