import CoreGraphics

struct BayerEffect: Effect {
    let declaration = EffectDeclaration(
        id: "bayer",
        name: "Bayer Dither",
        engine: .swiftPixel,
        parameters: [
            EffectParameter(id: "matrixSize", label: "Matrix", kind: .choice(options: ["2×2", "4×4", "8×8"], defaultValue: "4×4")),
        ],
        outputFormats: [.png],
        outputType: .raster
    )

    func render(input: CGImage, parameters: [String: ParameterValue]) async throws -> EffectOutput {
        let size = switch parameters["matrixSize"]?.choiceValue {
        case "2×2": 2
        case "8×8": 8
        default: 4
        }
        let matrix = Self.bayerMatrix(size: size)
        let cellCount = Float(size * size)

        let (source, width, height) = try PixelEngine.grayscaleBuffer(from: input)
        var output = [UInt8](repeating: 0, count: source.count)

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let value = Float(source[index]) / 255
                let threshold = (Float(matrix[y % size][x % size]) + 0.5) / cellCount
                output[index] = value > threshold ? 255 : 0
            }
        }

        return .image(try PixelEngine.grayscaleImage(from: output, width: width, height: height))
    }

    /// Recursively builds the standard Bayer matrix for size 2, 4, or 8.
    static func bayerMatrix(size: Int) -> [[Int]] {
        if size <= 2 {
            return [[0, 2], [3, 1]]
        }
        let half = size / 2
        let smaller = bayerMatrix(size: half)
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: size), count: size)
        for y in 0..<half {
            for x in 0..<half {
                let base = 4 * smaller[y][x]
                matrix[y][x] = base
                matrix[y][x + half] = base + 2
                matrix[y + half][x] = base + 3
                matrix[y + half][x + half] = base + 1
            }
        }
        return matrix
    }
}
