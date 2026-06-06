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
}
