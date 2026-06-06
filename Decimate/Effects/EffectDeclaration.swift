import Foundation

/// Which execution engine renders an effect.
enum EffectEngine {
    case coreImage      // built-in CoreImage filter
    case swiftPixel     // sequential per-pixel algorithm in Swift
    case python         // numerical/vector algorithm via Python subprocess
}

/// File formats an effect can export.
enum OutputFormat: String, CaseIterable, Identifiable {
    case png
    case svg

    var id: String { rawValue }
    var displayName: String { rawValue.uppercased() }
}

/// A single adjustable parameter, declared by an effect.
/// The shell renders UI from this — effects never build their own controls.
struct EffectParameter: Identifiable {
    let id: String      // key used in parameter value dictionaries and params JSON
    let label: String
    let kind: Kind

    enum Kind {
        case slider(range: ClosedRange<Double>, defaultValue: Double)
        case intSlider(range: ClosedRange<Int>, defaultValue: Int)
        case choice(options: [String], defaultValue: String)
    }

    var defaultValue: ParameterValue {
        switch kind {
        case .slider(_, let defaultValue): .double(defaultValue)
        case .intSlider(_, let defaultValue): .integer(defaultValue)
        case .choice(_, let defaultValue): .choice(defaultValue)
        }
    }
}

/// A concrete value for one parameter.
enum ParameterValue: Equatable {
    case double(Double)
    case integer(Int)
    case choice(String)

    var doubleValue: Double {
        switch self {
        case .double(let value): value
        case .integer(let value): Double(value)
        case .choice: 0
        }
    }

    var intValue: Int {
        switch self {
        case .double(let value): Int(value)
        case .integer(let value): value
        case .choice: 0
        }
    }

    var choiceValue: String? {
        if case .choice(let value) = self { return value }
        return nil
    }
}

/// Everything the shell needs to present and route an effect.
struct EffectDeclaration {
    let id: String
    let name: String
    let engine: EffectEngine
    let parameters: [EffectParameter]
    let outputFormats: [OutputFormat]

    var defaultParameterValues: [String: ParameterValue] {
        Dictionary(uniqueKeysWithValues: parameters.map { ($0.id, $0.defaultValue) })
    }
}
