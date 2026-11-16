import AppKit

struct RGB: Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    var rgbString: String { "rgb(\(r), \(g), \(b))" }

    private var unit: (Double, Double, Double) { (Double(r) / 255, Double(g) / 255, Double(b) / 255) }

    private var hue: Double {
        let (r, g, b) = unit
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        guard d > 0 else { return 0 }
        var h: Double
        if mx == r { h = (g - b) / d }
        else if mx == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h *= 60
        if h < 0 { h += 360 }
        return h
    }

    var hslString: String {
        let (r, g, b) = unit
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let l = (mx + mn) / 2
        let s = d == 0 ? 0 : d / (1 - abs(2 * l - 1))
        return "hsl(\(Int(hue.rounded()) % 360), \(pct(s)), \(pct(l)))"
    }

    var hsbString: String {
        let (r, g, b) = unit
        let mx = max(r, g, b), mn = min(r, g, b)
        let s = mx == 0 ? 0 : (mx - mn) / mx
        return "hsb(\(Int(hue.rounded()) % 360), \(pct(s)), \(pct(mx)))"
    }

    var cmykString: String {
        let (r, g, b) = unit
        let k = 1 - max(r, g, b)
        guard k < 1 else { return "cmyk(0%, 0%, 0%, 100%)" }
        let c = (1 - r - k) / (1 - k)
        let m = (1 - g - k) / (1 - k)
        let y = (1 - b - k) / (1 - k)
        return "cmyk(\(pct(c)), \(pct(m)), \(pct(y)), \(pct(k)))"
    }

    var formatRows: [(String, String)] {
        [("HEX", hex), ("RGB", rgbString), ("HSL", hslString), ("HSB", hsbString), ("CMYK", cmykString)]
    }

    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
}

final class PixelBuffer {
    let width: Int
    let height: Int
    private var data: [UInt8]

    init(image: CGImage) {
        width = image.width
        height = image.height
        data = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let w = width, h = height
        data.withUnsafeMutableBytes { ptr in
            if let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: w * 4, space: space,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
    }

    func contains(x: Int, y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height }

    func color(x: Int, y: Int) -> RGB {
        let cx = min(max(x, 0), width - 1), cy = min(max(y, 0), height - 1)
        let i = (cy * width + cx) * 4
        return RGB(r: data[i], g: data[i + 1], b: data[i + 2])
    }
}
