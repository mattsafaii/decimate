import CoreGraphics
import Foundation

/// Palette dithering in OKLab. Maps every pixel to the nearest palette colour by
/// perceptual distance (so matches read as the right colour, not the nearest in
/// muddy RGB), with a choice of error-diffusion kernels or ordered (Bayer)
/// dithering. Absorbs v1's grayscale Floyd–Steinberg and Bayer — now full colour
/// and palette-driven. Pure Swift; outputs a colour raster.
struct DitheringEffect: Effect {
    static let kernels = ["Floyd–Steinberg", "Atkinson", "Jarvis", "Ordered 4×4", "Ordered 8×8", "None"]

    let declaration = EffectDeclaration(
        id: "dithering",
        name: "Dithering",
        engine: .swiftPixel,
        parameters: [
            EffectParameter(id: "palette", label: "Palette", kind: .palette(defaultValue: .default)),
            EffectParameter(id: "kernel", label: "Kernel", kind: .choice(options: kernels, defaultValue: "Floyd–Steinberg")),
            EffectParameter(id: "strength", label: "Diffusion", kind: .slider(range: 0...1, defaultValue: 1)),
            EffectParameter(id: "serpentine", label: "Serpentine", kind: .toggle(defaultValue: true)),
        ],
        outputFormats: [.png],
        outputType: .raster
    )

    func render(input: CGImage, parameters: [String: ParameterValue]) async throws -> EffectOutput {
        let palette = parameters["palette"]?.paletteValue ?? .default
        let colors = palette.colors.isEmpty ? Palette.default.colors : palette.colors
        let kernel = parameters["kernel"]?.choiceValue ?? "Floyd–Steinberg"
        let strength = parameters["strength"]?.doubleValue ?? 1
        let serpentine = parameters["serpentine"]?.boolValue ?? true

        let paletteLab = colors.map { ColorConvert.oklab($0) }
        let paletteRGB = colors.map { c -> (UInt8, UInt8, UInt8) in
            (UInt8((c.red * 255).rounded()), UInt8((c.green * 255).rounded()), UInt8((c.blue * 255).rounded()))
        }

        let (source, width, height) = try PixelEngine.rgbaBuffer(from: input)
        let count = width * height

        // Source in OKLab (mutable for error diffusion); alpha preserved.
        var labL = [Double](repeating: 0, count: count)
        var labA = [Double](repeating: 0, count: count)
        var labB = [Double](repeating: 0, count: count)
        var alpha = [UInt8](repeating: 255, count: count)
        for i in 0..<count {
            let o = i * 4
            let lab = ColorConvert.oklab(
                r: Double(source[o]) / 255, g: Double(source[o + 1]) / 255, b: Double(source[o + 2]) / 255)
            labL[i] = lab.L; labA[i] = lab.a; labB[i] = lab.b
            alpha[i] = source[o + 3]
        }

        var output = [UInt8](repeating: 0, count: count * 4)

        func nearest(_ c: OKLab) -> Int {
            var best = 0, bd = Double.infinity
            for i in 0..<paletteLab.count {
                let d = c.distanceSquared(to: paletteLab[i])
                if d < bd { bd = d; best = i }
            }
            return best
        }

        func nearestTwo(_ c: OKLab) -> (Int, Int) {
            var best = 0, second = 0, bd = Double.infinity, sd = Double.infinity
            for i in 0..<paletteLab.count {
                let d = c.distanceSquared(to: paletteLab[i])
                if d < bd { sd = bd; second = best; bd = d; best = i }
                else if d < sd { sd = d; second = i }
            }
            return (best, second)
        }

        func write(_ index: Int, _ color: (UInt8, UInt8, UInt8)) {
            let o = index * 4
            output[o] = color.0; output[o + 1] = color.1; output[o + 2] = color.2; output[o + 3] = alpha[index]
        }

        if let matrixSize = orderedSize(kernel) {
            let matrix = Self.bayerMatrix(size: matrixSize)
            let cells = Double(matrixSize * matrixSize)
            for y in 0..<height {
                try Task.checkCancellation()
                for x in 0..<width {
                    let i = y * width + x
                    let pixel = OKLab(L: labL[i], a: labA[i], b: labB[i])
                    let (n1, n2) = nearestTwo(pixel)
                    let threshold = (Double(matrix[y % matrixSize][x % matrixSize]) + 0.5) / cells
                    write(i, paletteRGB[mix(pixel, paletteLab[n1], paletteLab[n2], n1, n2, threshold)])
                }
            }
        } else if let diffusion = Self.diffusion(kernel) {
            for y in 0..<height {
                try Task.checkCancellation()
                let reverse = serpentine && (y % 2 == 1)
                let xs = reverse ? Array((0..<width).reversed()) : Array(0..<width)
                for x in xs {
                    let i = y * width + x
                    let pixel = OKLab(L: labL[i], a: labA[i], b: labB[i])
                    let n = nearest(pixel)
                    write(i, paletteRGB[n])
                    let error = (pixel - paletteLab[n]) * strength
                    for (dx, dy, w) in diffusion {
                        let nx = x + (reverse ? -dx : dx)
                        let ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let j = ny * width + nx
                        labL[j] += error.L * w; labA[j] += error.a * w; labB[j] += error.b * w
                    }
                }
            }
        } else {  // None — straight nearest-colour posterize to the palette
            for y in 0..<height {
                try Task.checkCancellation()
                for x in 0..<width {
                    let i = y * width + x
                    write(i, paletteRGB[nearest(OKLab(L: labL[i], a: labA[i], b: labB[i]))])
                }
            }
        }

        return .image(try PixelEngine.rgbaImage(from: output, width: width, height: height))
    }

    /// Ordered dithering chooses between the two nearest palette colours based on
    /// how far the pixel leans toward the second and the Bayer threshold.
    private func mix(_ pixel: OKLab, _ c1: OKLab, _ c2: OKLab, _ i1: Int, _ i2: Int, _ threshold: Double) -> Int {
        let axis = c2 - c1
        let denom = axis.L * axis.L + axis.a * axis.a + axis.b * axis.b
        guard denom > 1e-9 else { return i1 }
        let d = pixel - c1
        let ratio = max(0, min(1, (d.L * axis.L + d.a * axis.a + d.b * axis.b) / denom))
        return ratio > threshold ? i2 : i1
    }

    private func orderedSize(_ kernel: String) -> Int? {
        switch kernel {
        case "Ordered 4×4": 4
        case "Ordered 8×8": 8
        default: nil
        }
    }

    /// (dx, dy, weight) error-diffusion taps; nil for non-diffusion kernels.
    static func diffusion(_ kernel: String) -> [(Int, Int, Double)]? {
        switch kernel {
        case "Floyd–Steinberg":
            [(1, 0, 7 / 16), (-1, 1, 3 / 16), (0, 1, 5 / 16), (1, 1, 1 / 16)]
        case "Atkinson":
            [(1, 0, 1 / 8), (2, 0, 1 / 8), (-1, 1, 1 / 8), (0, 1, 1 / 8), (1, 1, 1 / 8), (0, 2, 1 / 8)]
        case "Jarvis":
            [(1, 0, 7 / 48), (2, 0, 5 / 48),
             (-2, 1, 3 / 48), (-1, 1, 5 / 48), (0, 1, 7 / 48), (1, 1, 5 / 48), (2, 1, 3 / 48),
             (-2, 2, 1 / 48), (-1, 2, 3 / 48), (0, 2, 5 / 48), (1, 2, 3 / 48), (2, 2, 1 / 48)]
        default:
            nil
        }
    }

    /// Standard recursive Bayer matrix for size 2, 4, or 8.
    static func bayerMatrix(size: Int) -> [[Int]] {
        if size <= 2 { return [[0, 2], [3, 1]] }
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
