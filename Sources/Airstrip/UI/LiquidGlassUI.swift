import SwiftUI

/// Shared visual treatment for custom Airstrip surfaces. On macOS 26 and newer
/// this uses Liquid Glass; older systems keep a tunable material fallback.
extension View {
    func airstripGlassPanel(
        cornerRadius: CGFloat = 12,
        tint: Color? = nil,
        interactive: Bool = false,
        fallbackOpacity: Double = 0.55
    ) -> some View {
        modifier(AirstripGlassPanelModifier(
            cornerRadius: cornerRadius,
            tint: tint,
            interactive: interactive,
            fallbackOpacity: fallbackOpacity
        ))
    }

    @ViewBuilder
    func airstripGlassPanel(
        isPresented: Bool,
        cornerRadius: CGFloat = 12,
        tint: Color? = nil,
        interactive: Bool = false,
        fallbackOpacity: Double = 0.55
    ) -> some View {
        if isPresented {
            airstripGlassPanel(
                cornerRadius: cornerRadius,
                tint: tint,
                interactive: interactive,
                fallbackOpacity: fallbackOpacity
            )
        } else {
            self
        }
    }

    func airstripGlassCapsule(tint: Color? = nil, interactive: Bool = false, isToolbarItem: Bool = false) -> some View {
        modifier(AirstripGlassCapsuleModifier(tint: tint, interactive: interactive, isToolbarItem: isToolbarItem))
    }

    @ViewBuilder
    func airstripGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }

    func softenedByVisualSettings() -> some View {
        modifier(AirstripColorSofteningModifier())
    }
}

private struct AirstripGlassPanelModifier: ViewModifier {
    @Environment(\.airstripVisualStyle) private var visualStyle

    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool
    let fallbackOpacity: Double

    func body(content: Content) -> some View {
        let radius = cornerRadius * visualStyle.cornerScale
        let tint = tint?.opacity(visualStyle.tintStrength * visualStyle.colorIntensity)

        if #available(macOS 26.0, *) {
            let glass = configuredGlass(tint: tint, interactive: interactive)
            content.glassEffect(glass, in: .rect(cornerRadius: radius))
        } else {
            content
                .background(.regularMaterial.opacity(visualStyle.glassOpacity), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .background((tint ?? .clear).opacity(fallbackOpacity * 0.18), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder((tint ?? Color.primary).opacity(tint == nil ? 0.08 : 0.24), lineWidth: 1)
                }
        }
    }

    @available(macOS 26.0, *)
    private func configuredGlass(tint: Color?, interactive: Bool) -> Glass {
        let base = tint.map { Glass.regular.tint($0) } ?? .regular
        return interactive ? base.interactive() : base
    }
}

private struct AirstripGlassCapsuleModifier: ViewModifier {
    @Environment(\.airstripVisualStyle) private var visualStyle

    let tint: Color?
    let interactive: Bool
    let isToolbarItem: Bool

    func body(content: Content) -> some View {
        let tint = tint?.opacity(visualStyle.tintStrength * visualStyle.colorIntensity)

        if #available(macOS 26.0, *) {
            let glass = configuredGlass(tint: tint, interactive: interactive)
            content.glassEffect(glass)
        } else {
            if isToolbarItem {
                content
            } else {
                content
                    .background(.thinMaterial.opacity(visualStyle.glassOpacity), in: Capsule())
                    .background((tint ?? .clear).opacity(0.14), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder((tint ?? Color.primary).opacity(tint == nil ? 0.08 : 0.24), lineWidth: 1)
                    }
            }
        }
    }

    @available(macOS 26.0, *)
    private func configuredGlass(tint: Color?, interactive: Bool) -> Glass {
        let base = tint.map { Glass.regular.tint($0) } ?? .regular
        return interactive ? base.interactive() : base
    }
}

private struct AirstripColorSofteningModifier: ViewModifier {
    @Environment(\.airstripVisualStyle) private var visualStyle

    func body(content: Content) -> some View {
        content.saturation(visualStyle.colorIntensity)
    }
}
