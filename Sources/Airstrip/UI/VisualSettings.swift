import SwiftUI

struct AirstripVisualStyle: Equatable {
    var glassOpacity: Double = 0.42
    var tintStrength: Double = 0.55
    var colorIntensity: Double = 0.72
    var cornerScale: Double = 1.0
    var toolbarControlHeight: Double = 32
    var toolbarIconSize: Double = 15
    var toolbarSpacing: Double = 8
    var separatorOpacity: Double = 0.35

    static let `default` = AirstripVisualStyle()
}

private struct AirstripVisualStyleKey: EnvironmentKey {
    static let defaultValue = AirstripVisualStyle.default
}

extension EnvironmentValues {
    var airstripVisualStyle: AirstripVisualStyle {
        get { self[AirstripVisualStyleKey.self] }
        set { self[AirstripVisualStyleKey.self] = newValue }
    }
}

final class VisualSettings: ObservableObject {
    @Published var style: AirstripVisualStyle {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.style = AirstripVisualStyle(
            glassOpacity: defaults.object(forKey: Keys.glassOpacity) as? Double ?? AirstripVisualStyle.default.glassOpacity,
            tintStrength: defaults.object(forKey: Keys.tintStrength) as? Double ?? AirstripVisualStyle.default.tintStrength,
            colorIntensity: defaults.object(forKey: Keys.colorIntensity) as? Double ?? AirstripVisualStyle.default.colorIntensity,
            cornerScale: defaults.object(forKey: Keys.cornerScale) as? Double ?? AirstripVisualStyle.default.cornerScale,
            toolbarControlHeight: defaults.object(forKey: Keys.toolbarControlHeight) as? Double ?? AirstripVisualStyle.default.toolbarControlHeight,
            toolbarIconSize: defaults.object(forKey: Keys.toolbarIconSize) as? Double ?? AirstripVisualStyle.default.toolbarIconSize,
            toolbarSpacing: defaults.object(forKey: Keys.toolbarSpacing) as? Double ?? AirstripVisualStyle.default.toolbarSpacing,
            separatorOpacity: defaults.object(forKey: Keys.separatorOpacity) as? Double ?? AirstripVisualStyle.default.separatorOpacity
        )
    }

    func reset() {
        style = .default
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let glassOpacity = "visual.glassOpacity"
        static let tintStrength = "visual.tintStrength"
        static let colorIntensity = "visual.colorIntensity"
        static let cornerScale = "visual.cornerScale"
        static let toolbarControlHeight = "visual.toolbarControlHeight"
        static let toolbarIconSize = "visual.toolbarIconSize"
        static let toolbarSpacing = "visual.toolbarSpacing"
        static let separatorOpacity = "visual.separatorOpacity"
    }

    private func save() {
        defaults.set(style.glassOpacity, forKey: Keys.glassOpacity)
        defaults.set(style.tintStrength, forKey: Keys.tintStrength)
        defaults.set(style.colorIntensity, forKey: Keys.colorIntensity)
        defaults.set(style.cornerScale, forKey: Keys.cornerScale)
        defaults.set(style.toolbarControlHeight, forKey: Keys.toolbarControlHeight)
        defaults.set(style.toolbarIconSize, forKey: Keys.toolbarIconSize)
        defaults.set(style.toolbarSpacing, forKey: Keys.toolbarSpacing)
        defaults.set(style.separatorOpacity, forKey: Keys.separatorOpacity)
    }
}

struct VisualTuningPanel: View {
    @EnvironmentObject private var visualSettings: VisualSettings
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Visual Tuning")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button("Reset") { visualSettings.reset() }
                    .airstripGlassButton()
                    .controlSize(.small)
                    .noFocusRing()

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .noFocusRing()
                .help("Close visual tuning")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    tuningSlider(
                        "Glass Opacity",
                        value: binding(\.glassOpacity),
                        range: 0.15...0.85,
                        detail: "Controls fallback material weight and non-Liquid-Glass surface density."
                    )

                    tuningSlider(
                        "Tint Strength",
                        value: binding(\.tintStrength),
                        range: 0...1,
                        detail: "Reduces or increases colored glass tints on active surfaces."
                    )

                    tuningSlider(
                        "Color Intensity",
                        value: binding(\.colorIntensity),
                        range: 0.25...1,
                        detail: "Softens project, success, warning, and accent colors without changing layout."
                    )

                    tuningSlider(
                        "Corner Scale",
                        value: binding(\.cornerScale),
                        range: 0.65...1.45,
                        detail: "Scales rounded corners across custom panels and controls."
                    )

                    Divider()

                    tuningSlider(
                        "Toolbar Height",
                        value: binding(\.toolbarControlHeight),
                        range: 26...40,
                        step: 1,
                        detail: "Matches custom toolbar controls to native macOS toolbar proportions."
                    )

                    tuningSlider(
                        "Toolbar Icon Size",
                        value: binding(\.toolbarIconSize),
                        range: 12...19,
                        step: 1,
                        detail: "Adjusts icon weight inside toolbar glass controls."
                    )

                    tuningSlider(
                        "Toolbar Spacing",
                        value: binding(\.toolbarSpacing),
                        range: 4...16,
                        step: 1,
                        detail: "Controls horizontal spacing between toolbar controls."
                    )

                    tuningSlider(
                        "Separator Opacity",
                        value: binding(\.separatorOpacity),
                        range: 0...0.8,
                        detail: "Controls divider strength around chrome and sidebars."
                    )
                }
                .padding(20)
            }
        }
        .airstripGlassPanel(cornerRadius: 18, interactive: true, fallbackOpacity: 0.7)
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
    }

    private func binding(_ keyPath: WritableKeyPath<AirstripVisualStyle, Double>) -> Binding<Double> {
        Binding(
            get: { visualSettings.style[keyPath: keyPath] },
            set: { visualSettings.style[keyPath: keyPath] = $0 }
        )
    }

    private func tuningSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))

                Spacer()

                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(step == nil ? 2 : 0))))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let step {
                Slider(value: value, in: range, step: step)
            } else {
                Slider(value: value, in: range)
            }

            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }
}
