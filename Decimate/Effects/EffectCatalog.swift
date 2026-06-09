/// The effect registry. The shell reads this list and nothing else —
/// new effects are added here and picked up automatically.
enum EffectCatalog {
    static let all: [any Effect] = [
        StipplingEffect(),
        EngravingEffect(),
        FloydSteinbergEffect(),
        BayerEffect(),
    ]

    static func effect(id: String) -> (any Effect)? {
        all.first { $0.declaration.id == id }
    }
}
