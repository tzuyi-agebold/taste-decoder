import SwiftUI

/// Procedural artwork for demo saves and Learn card examples.
/// Deterministic per seed, resolution-independent, and drawn with Canvas — no bundled photos.
enum ArtStyle: String, Codable, CaseIterable {
    /// Acid color, distorted forms, harsh flash hotspot.
    case uncomfy
    /// Burgundy depths, candle glow, a glass-rim ring.
    case wine
    /// Walnut floor, low seating, a single warm lamp.
    case room
    /// Night blues, reverb blooms, a waveform.
    case night
    /// Two-color risograph print with misregistration.
    case riso
    /// Generic poster for Learn examples.
    case poster
}

struct PlaceholderArt: View {
    let style: ArtStyle
    let seed: Int
    /// Off-main rendering for scrolling grids; turn off when rendering to an image.
    var rendersAsynchronously = true

    var body: some View {
        Canvas(rendersAsynchronously: rendersAsynchronously) { context, size in
            var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: seed &* 2_654_435_761 &+ 97))
            switch style {
            case .uncomfy: Self.drawUncomfy(&context, size, &rng)
            case .wine: Self.drawWine(&context, size, &rng)
            case .room: Self.drawRoom(&context, size, &rng)
            case .night: Self.drawNight(&context, size, &rng)
            case .riso: Self.drawRiso(&context, size, &rng)
            case .poster: Self.drawPoster(&context, size, &rng)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Uncomfy — distortion, flash, acid

    private static func drawUncomfy(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        let palette: [Color] = [
            Color(hex: 0xC6FF00), Color(hex: 0xFF2E93), Color(hex: 0xF4FF52),
            Color(hex: 0x00F0FF), Color(hex: 0xFF5A1F),
        ]
        let rect = CGRect(origin: .zero, size: size)
        let background = palette[rng.int(palette.count)]
        var figure = palette[rng.int(palette.count)]
        if figure == background { figure = Color(hex: 0x1A1A1A) }
        ctx.fill(Path(rect), with: .color(background))

        let unit = min(size.width, size.height)
        let center = CGPoint(x: size.width * rng.range(0.38...0.62), y: size.height * rng.range(0.4...0.58))
        let radius = unit * rng.range(0.22...0.3)
        let stretchX = rng.range(0.55...0.85)
        let stretchY = rng.range(1.25...1.8)
        let tilt = Angle.degrees(Double(rng.range(-20...20)))

        // Hard shadow thrown by an on-camera flash.
        ctx.drawLayer { layer in
            layer.translateBy(x: center.x + unit * 0.05, y: center.y + unit * 0.06)
            layer.rotate(by: tilt)
            layer.scaleBy(x: stretchX, y: stretchY)
            layer.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                       with: .color(.black.opacity(0.55)))
        }
        // The distorted figure.
        ctx.drawLayer { layer in
            layer.translateBy(x: center.x, y: center.y)
            layer.rotate(by: tilt)
            layer.scaleBy(x: stretchX, y: stretchY)
            layer.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                       with: .color(figure))
            // Two mismatched eyes.
            let eyeY = -radius * 0.25
            let left = radius * rng.range(0.12...0.2)
            let right = radius * rng.range(0.2...0.34)
            layer.fill(Path(ellipseIn: CGRect(x: -radius * 0.45 - left, y: eyeY - left, width: left * 2, height: left * 2)), with: .color(.black))
            layer.fill(Path(ellipseIn: CGRect(x: radius * 0.4 - right, y: eyeY - right * 0.7, width: right * 2, height: right * 1.4)), with: .color(.black))
        }
        // Flash hotspot.
        let hotspot = CGPoint(x: size.width * rng.range(0.35...0.55), y: size.height * rng.range(0.3...0.45))
        ctx.fill(Path(rect), with: .radialGradient(
            Gradient(stops: [
                .init(color: .white.opacity(0.85), location: 0),
                .init(color: .white.opacity(0.3), location: 0.28),
                .init(color: .white.opacity(0), location: 0.6),
            ]),
            center: hotspot, startRadius: 0, endRadius: unit * 0.7))
        vignette(&ctx, size, strength: 0.55)
        grain(&ctx, size, &rng, density: 0.9)
    }

    // MARK: Wine — burgundy, candle, glass ring

    private static func drawWine(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        let rect = CGRect(origin: .zero, size: size)
        let tops: [Color] = [Color(hex: 0x2A0610), Color(hex: 0x1E0508), Color(hex: 0x33080F)]
        let bottoms: [Color] = [Color(hex: 0x5B0F1F), Color(hex: 0x6E1A1A), Color(hex: 0x4A0B24)]
        let i = rng.int(tops.count)
        ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [tops[i], bottoms[i]]),
                                                    startPoint: .zero, endPoint: CGPoint(x: size.width * 0.3, y: size.height)))
        let unit = min(size.width, size.height)
        // Candle glow.
        let glow = CGPoint(x: size.width * rng.range(0.15...0.85), y: size.height * rng.range(0.15...0.4))
        ctx.fill(Path(rect), with: .radialGradient(
            Gradient(colors: [Color(hex: 0xE39A45).opacity(0.55), Color(hex: 0xE39A45).opacity(0)]),
            center: glow, startRadius: 0, endRadius: unit * 0.6))
        // Glass-rim ring stain.
        let ringCenter = CGPoint(x: size.width * rng.range(0.35...0.65), y: size.height * rng.range(0.55...0.72))
        let r = unit * rng.range(0.22...0.3)
        let ring = Path(ellipseIn: CGRect(x: ringCenter.x - r, y: ringCenter.y - r * 0.35, width: r * 2, height: r * 0.7))
        ctx.stroke(ring, with: .color(Color(hex: 0xB8323F).opacity(0.75)), lineWidth: unit * 0.018)
        ctx.fill(ring, with: .color(Color(hex: 0x7A0E1E).opacity(0.55)))
        // A glint of caramel light on the rim.
        ctx.stroke(Path(ellipseIn: CGRect(x: ringCenter.x - r * 0.9, y: ringCenter.y - r * 0.3, width: r * 1.1, height: r * 0.3)),
                   with: .color(Color(hex: 0xF3C07A).opacity(0.35)), lineWidth: unit * 0.006)
        vignette(&ctx, size, strength: 0.6)
        grain(&ctx, size, &rng, density: 0.6)
    }

    // MARK: Room — walnut, low seating, one warm lamp

    private static func drawRoom(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        let rect = CGRect(origin: .zero, size: size)
        ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(hex: 0x120C09), Color(hex: 0x2B1D14)]),
                                                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let floorY = size.height * rng.range(0.66...0.74)
        let floor = CGRect(x: 0, y: floorY, width: size.width, height: size.height - floorY)
        ctx.fill(Path(floor), with: .linearGradient(Gradient(colors: [Color(hex: 0x5A3A22), Color(hex: 0x3B2415)]),
                                                     startPoint: CGPoint(x: 0, y: floorY), endPoint: CGPoint(x: 0, y: size.height)))
        // Walnut grain.
        for _ in 0..<14 {
            let y = floorY + rng.range(0.04...0.96) * floor.height
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addCurve(to: CGPoint(x: size.width, y: y + rng.range(-6...6)),
                          control1: CGPoint(x: size.width * 0.3, y: y + rng.range(-5...5)),
                          control2: CGPoint(x: size.width * 0.7, y: y + rng.range(-5...5)))
            ctx.stroke(line, with: .color(Color(hex: 0x24150C).opacity(0.5)), lineWidth: 1)
        }
        // Warm directional light from a lamp on one side.
        let fromLeft = rng.bool()
        let lampX = fromLeft ? size.width * rng.range(0.12...0.28) : size.width * rng.range(0.72...0.88)
        let lampY = size.height * rng.range(0.36...0.48)
        var cone = Path()
        cone.move(to: CGPoint(x: lampX - 6, y: lampY))
        cone.addLine(to: CGPoint(x: lampX + 6, y: lampY))
        cone.addLine(to: CGPoint(x: lampX + size.width * 0.32, y: size.height))
        cone.addLine(to: CGPoint(x: lampX - size.width * 0.32, y: size.height))
        cone.closeSubpath()
        ctx.fill(cone, with: .linearGradient(Gradient(colors: [Color(hex: 0xFFB866).opacity(0.5), Color(hex: 0xFFB866).opacity(0)]),
                                             startPoint: CGPoint(x: lampX, y: lampY), endPoint: CGPoint(x: lampX, y: size.height)))
        ctx.fill(Path(rect), with: .radialGradient(
            Gradient(colors: [Color(hex: 0xFFC77A).opacity(0.7), Color(hex: 0xFFC77A).opacity(0)]),
            center: CGPoint(x: lampX, y: lampY), startRadius: 0, endRadius: min(size.width, size.height) * 0.45))
        // Lamp shade.
        let shade = CGRect(x: lampX - size.width * 0.06, y: lampY - size.height * 0.07, width: size.width * 0.12, height: size.height * 0.07)
        ctx.fill(Path(roundedRect: shade, cornerRadius: 3), with: .color(Color(hex: 0xF4D7A8)))
        // Low-profile sofa.
        let sofaColors: [Color] = [Color(hex: 0x8B5A3C), Color(hex: 0xC9B8A0), Color(hex: 0x3E4A3A), Color(hex: 0x6B2E22)]
        let sofaColor = sofaColors[rng.int(sofaColors.count)]
        let sofaWidth = size.width * rng.range(0.5...0.66)
        let sofaX = fromLeft ? size.width - sofaWidth - size.width * 0.08 : size.width * 0.08
        let sofaHeight = size.height * 0.1
        let sofa = CGRect(x: sofaX, y: floorY - sofaHeight * 0.75, width: sofaWidth, height: sofaHeight)
        ctx.fill(Path(roundedRect: sofa, cornerRadius: sofaHeight * 0.35), with: .color(sofaColor))
        let back = CGRect(x: sofaX, y: sofa.minY - sofaHeight * 0.55, width: sofaWidth, height: sofaHeight * 0.7)
        ctx.fill(Path(roundedRect: back, cornerRadius: sofaHeight * 0.3), with: .color(sofaColor.opacity(0.85)))
        ctx.fill(Path(CGRect(x: sofaX + 6, y: sofa.maxY - 3, width: sofaWidth - 12, height: 6)), with: .color(.black.opacity(0.35)))
        vignette(&ctx, size, strength: 0.5)
        grain(&ctx, size, &rng, density: 0.5)
    }

    // MARK: Night — blues, bloom, waveform

    private static func drawNight(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        let rect = CGRect(origin: .zero, size: size)
        ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(hex: 0x05060F), Color(hex: 0x141A3A)]),
                                                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let unit = min(size.width, size.height)
        let blooms: [Color] = [Color(hex: 0x3D5AFE), Color(hex: 0x7C4DFF), Color(hex: 0xFF6E91), Color(hex: 0x2EC5FF), Color(hex: 0xFFB74D)]
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: unit * 0.09))
            for _ in 0..<4 {
                let r = unit * rng.range(0.12...0.3)
                let c = CGPoint(x: size.width * rng.range(0.1...0.9), y: size.height * rng.range(0.15...0.85))
                layer.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                           with: .color(blooms[rng.int(blooms.count)].opacity(Double(rng.range(0.35...0.7)))))
            }
        }
        // Waveform.
        var wave = Path()
        let midY = size.height * rng.range(0.55...0.7)
        let amplitude = unit * rng.range(0.03...0.07)
        let frequency = rng.range(2.5...5)
        wave.move(to: CGPoint(x: 0, y: midY))
        for step in stride(from: CGFloat(0), through: size.width, by: 3) {
            let t: CGFloat = step / max(size.width, 1)
            let envelope: CGFloat = sin(CGFloat.pi * t)
            let phase: CGFloat = t * CGFloat.pi * 2 * frequency
            wave.addLine(to: CGPoint(x: step, y: midY + sin(phase) * amplitude * envelope))
        }
        ctx.stroke(wave, with: .color(.white.opacity(0.55)), lineWidth: 1.5)
        // Moon.
        let moon = CGPoint(x: size.width * rng.range(0.65...0.85), y: size.height * rng.range(0.12...0.25))
        let mr = unit * 0.045
        ctx.fill(Path(ellipseIn: CGRect(x: moon.x - mr, y: moon.y - mr, width: mr * 2, height: mr * 2)), with: .color(.white.opacity(0.85)))
        vignette(&ctx, size, strength: 0.4)
        grain(&ctx, size, &rng, density: 0.7)
    }

    // MARK: Riso — two spot colors, misregistered

    private static func drawRiso(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        let rect = CGRect(origin: .zero, size: size)
        ctx.fill(Path(rect), with: .color(Color(hex: 0xF2EDE4)))
        let pink = Color(hex: 0xFF48B0)
        let blue = Color(hex: 0x0078BF)
        let unit = min(size.width, size.height)
        ctx.blendMode = .multiply
        // Halftone disc in blue.
        let c1 = CGPoint(x: size.width * rng.range(0.35...0.6), y: size.height * rng.range(0.35...0.55))
        let r1 = unit * rng.range(0.28...0.36)
        let spacing = unit * 0.035
        var dots = Path()
        var y = c1.y - r1
        while y <= c1.y + r1 {
            var x = c1.x - r1
            while x <= c1.x + r1 {
                let d = hypot(x - c1.x, y - c1.y)
                if d < r1 {
                    let dotR = spacing * 0.45 * (1 - d / r1 * 0.7)
                    dots.addEllipse(in: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2))
                }
                x += spacing
            }
            y += spacing
        }
        ctx.fill(dots, with: .color(blue.opacity(0.9)))
        // Solid pink shape, misregistered.
        let offset = unit * 0.02
        let r2 = unit * rng.range(0.2...0.28)
        let c2 = CGPoint(x: c1.x + r1 * rng.range(-0.6...0.6) + offset, y: c1.y + r1 * rng.range(0.1...0.6) + offset)
        ctx.fill(Path(ellipseIn: CGRect(x: c2.x - r2, y: c2.y - r2, width: r2 * 2, height: r2 * 2)), with: .color(pink.opacity(0.85)))
        // Hand-cut bar.
        let bar = CGRect(x: size.width * 0.12, y: size.height * rng.range(0.75...0.85), width: size.width * rng.range(0.4...0.7), height: unit * 0.05)
        ctx.fill(Path(bar), with: .color(blue.opacity(0.8)))
        ctx.blendMode = .normal
        grain(&ctx, size, &rng, density: 1.1)
    }

    // MARK: Poster — for Learn examples

    private static func drawPoster(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom) {
        let rect = CGRect(origin: .zero, size: size)
        let hue = rng.unit()
        let a = Color(hue: hue, saturation: 0.55, brightness: 0.28)
        let b = Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.65, brightness: 0.55)
        ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [a, b]), startPoint: .zero,
                                                    endPoint: CGPoint(x: size.width, y: size.height)))
        let unit = min(size.width, size.height)
        let shapeColor = Color(hue: (hue + 0.5).truncatingRemainder(dividingBy: 1), saturation: 0.5, brightness: 0.95).opacity(0.85)
        let center = CGPoint(x: size.width * rng.range(0.3...0.7), y: size.height * rng.range(0.3...0.6))
        let r = unit * rng.range(0.18...0.32)
        switch rng.int(3) {
        case 0:
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(shapeColor))
        case 1:
            ctx.fill(Path(CGRect(x: center.x - r, y: center.y - r * 0.6, width: r * 2, height: r * 1.2)), with: .color(shapeColor))
        default:
            var tri = Path()
            tri.move(to: CGPoint(x: center.x, y: center.y - r))
            tri.addLine(to: CGPoint(x: center.x + r, y: center.y + r * 0.8))
            tri.addLine(to: CGPoint(x: center.x - r, y: center.y + r * 0.8))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(shapeColor))
        }
        vignette(&ctx, size, strength: 0.35)
        grain(&ctx, size, &rng, density: 0.5)
    }

    // MARK: Shared finishing

    private static func vignette(_ ctx: inout GraphicsContext, _ size: CGSize, strength: Double) {
        let rect = CGRect(origin: .zero, size: size)
        ctx.fill(Path(rect), with: .radialGradient(
            Gradient(colors: [.black.opacity(0), .black.opacity(strength)]),
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            startRadius: min(size.width, size.height) * 0.35,
            endRadius: max(size.width, size.height) * 0.8))
    }

    private static func grain(_ ctx: inout GraphicsContext, _ size: CGSize, _ rng: inout SeededRandom, density: Double) {
        let count = Int(min(size.width * size.height / 500, 700) * density)
        var light = Path()
        var dark = Path()
        for index in 0..<count {
            let dot = CGRect(x: CGFloat(rng.unit()) * size.width, y: CGFloat(rng.unit()) * size.height, width: 1.2, height: 1.2)
            if index.isMultiple(of: 2) { light.addRect(dot) } else { dark.addRect(dot) }
        }
        ctx.fill(light, with: .color(.white.opacity(0.09)))
        ctx.fill(dark, with: .color(.black.opacity(0.12)))
    }
}

// MARK: - Helpers

/// SplitMix64: tiny, fast, deterministic.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    /// Geometry-friendly random value.
    mutating func range(_ range: ClosedRange<CGFloat>) -> CGFloat { range.lowerBound + CGFloat(unit()) * (range.upperBound - range.lowerBound) }
    mutating func int(_ upperBound: Int) -> Int { Int(next() % UInt64(max(upperBound, 1))) }
    mutating func bool() -> Bool { next() & 1 == 1 }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Stable 64-bit hash for strings (FNV-1a), so art stays the same across launches.
enum StableHash {
    static func int(_ string: String) -> Int {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Int(truncatingIfNeeded: hash)
    }
}
