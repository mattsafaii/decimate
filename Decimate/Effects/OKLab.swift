import Foundation

/// A color in the OKLab perceptual space — Euclidean distance here approximates
/// perceived color difference, which makes palette matching and error diffusion
/// look right (no muddy nearest-color picks the way naive RGB distance gives).
struct OKLab {
    var L: Double
    var a: Double
    var b: Double

    /// Squared perceptual distance — cheap (no sqrt) and monotonic, fine for
    /// nearest-color search.
    func distanceSquared(to other: OKLab) -> Double {
        let dL = L - other.L, da = a - other.a, db = b - other.b
        return dL * dL + da * da + db * db
    }

    static func + (lhs: OKLab, rhs: OKLab) -> OKLab {
        OKLab(L: lhs.L + rhs.L, a: lhs.a + rhs.a, b: lhs.b + rhs.b)
    }

    static func - (lhs: OKLab, rhs: OKLab) -> OKLab {
        OKLab(L: lhs.L - rhs.L, a: lhs.a - rhs.a, b: lhs.b - rhs.b)
    }

    static func * (lhs: OKLab, rhs: Double) -> OKLab {
        OKLab(L: lhs.L * rhs, a: lhs.a * rhs, b: lhs.b * rhs)
    }
}

enum ColorConvert {
    static func srgbToLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func linearToSrgb(_ c: Double) -> Double {
        let v = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        return min(1, max(0, v))
    }

    /// sRGB components (0...1) → OKLab.
    static func oklab(r: Double, g: Double, b: Double) -> OKLab {
        let lr = srgbToLinear(r), lg = srgbToLinear(g), lb = srgbToLinear(b)
        let l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
        let m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
        let s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        return OKLab(
            L: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        )
    }

    static func oklab(_ color: ColorValue) -> OKLab {
        oklab(r: color.red, g: color.green, b: color.blue)
    }
}
