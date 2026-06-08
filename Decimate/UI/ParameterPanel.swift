import SwiftUI

/// Renders parameter controls from effect declarations. Knows nothing about
/// specific effects — sliders and pickers come straight from the declaration.
struct ParameterPanel: View {
    let parameters: [EffectParameter]
    @Binding var values: [String: ParameterValue]

    var body: some View {
        ForEach(parameters) { parameter in
            control(for: parameter)
        }
    }

    @ViewBuilder
    private func control(for parameter: EffectParameter) -> some View {
        switch parameter.kind {
        case .slider(let range, let defaultValue):
            LabeledContent(parameter.label) {
                HStack {
                    Slider(value: doubleBinding(parameter.id, defaultValue: defaultValue), in: range)
                    Text(doubleBinding(parameter.id, defaultValue: defaultValue).wrappedValue,
                         format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
            }
        case .intSlider(let range, let defaultValue):
            LabeledContent(parameter.label) {
                HStack {
                    Slider(
                        value: intSliderBinding(parameter.id, defaultValue: defaultValue),
                        in: Double(range.lowerBound)...Double(range.upperBound),
                        step: 1
                    )
                    Text("\(intBinding(parameter.id, defaultValue: defaultValue).wrappedValue)")
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
            }
        case .choice(let options, let defaultValue):
            Picker(parameter.label, selection: choiceBinding(parameter.id, defaultValue: defaultValue)) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        case .toggle(let defaultValue):
            Toggle(parameter.label, isOn: boolBinding(parameter.id, defaultValue: defaultValue))
        case .color(let defaultValue):
            ColorPicker(parameter.label, selection: colorBinding(parameter.id, defaultValue: defaultValue))
        case .palette(let defaultValue):
            PaletteControl(palette: paletteBinding(parameter.id, defaultValue: defaultValue), label: parameter.label)
        }
    }

    private func doubleBinding(_ id: String, defaultValue: Double) -> Binding<Double> {
        Binding(
            get: { values[id]?.doubleValue ?? defaultValue },
            set: { values[id] = .double($0) }
        )
    }

    private func intBinding(_ id: String, defaultValue: Int) -> Binding<Int> {
        Binding(
            get: { values[id]?.intValue ?? defaultValue },
            set: { values[id] = .integer($0) }
        )
    }

    private func intSliderBinding(_ id: String, defaultValue: Int) -> Binding<Double> {
        Binding(
            get: { Double(values[id]?.intValue ?? defaultValue) },
            set: { values[id] = .integer(Int($0.rounded())) }
        )
    }

    private func choiceBinding(_ id: String, defaultValue: String) -> Binding<String> {
        Binding(
            get: { values[id]?.choiceValue ?? defaultValue },
            set: { values[id] = .choice($0) }
        )
    }

    private func boolBinding(_ id: String, defaultValue: Bool) -> Binding<Bool> {
        Binding(
            get: { values[id]?.boolValue ?? defaultValue },
            set: { values[id] = .bool($0) }
        )
    }

    private func colorBinding(_ id: String, defaultValue: ColorValue) -> Binding<Color> {
        Binding(
            get: { Color(values[id]?.colorValue ?? defaultValue) },
            set: { values[id] = .color(ColorValue($0)) }
        )
    }

    private func paletteBinding(_ id: String, defaultValue: Palette) -> Binding<Palette> {
        Binding(
            get: { values[id]?.paletteValue ?? defaultValue },
            set: { values[id] = .palette($0) }
        )
    }
}

/// Minimal palette display — a labeled row of swatches. The full editor
/// (add/remove/reorder, bundled presets) is built on this binding later.
private struct PaletteControl: View {
    @Binding var palette: Palette
    let label: String

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 2) {
                ForEach(Array(palette.colors.enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(color))
                        .frame(width: 16, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.separator))
                }
            }
        }
    }
}

extension Color {
    init(_ value: ColorValue) {
        self.init(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }
}

extension ColorValue {
    /// Reads sRGB components from a SwiftUI Color via NSColor (macOS).
    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        self.init(
            red: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent),
            alpha: Double(resolved.alphaComponent)
        )
    }
}
