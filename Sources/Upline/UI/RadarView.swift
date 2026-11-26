import AppKit
import SwiftUI

/// The live radar. Every watched service is a blip: active projects sit on the inner ring,
/// idle ones further out, dormant ones on the edge. Blips light up as the sweep passes them,
/// and services with problems pulse.
struct RadarView: View {
    struct Blip: Identifiable {
        let id: String
        let angle: Double
        let radius: Double
        let health: Health
        let tint: Color
    }

    let services: [WatchedService]
    var size: CGFloat = 132
    var scanning = false
    var accent: Color = Theme.cyan
    @State private var visible = false

    private var blips: [Blip] {
        services.map { s in
            let radius: Double = switch s.tier {
            case .active: 0.42
            case .idle: 0.66
            case .stale: 0.88
            }
            return Blip(id: s.id, angle: Self.stableAngle(s.id), radius: radius + Self.jitter(s.id), health: s.state.health, tint: Color(hex: s.entry.color))
        }
    }

    static func stableAngle(_ id: String) -> Double {
        var h: UInt64 = 1469598103934665603
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Double(h % 3600) / 3600 * 2 * .pi
    }

    static func jitter(_ id: String) -> Double {
        var h: UInt64 = 7
        for b in id.utf8 { h = h &* 31 &+ UInt64(b) }
        return (Double(h % 100) / 100 - 0.5) * 0.12
    }

    var body: some View {
        let blips = self.blips
        TimelineView(.animation(minimumInterval: 1 / 40, paused: !visible)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, sz in
                draw(&g, size: sz, t: t, blips: blips)
            }
        }
        .frame(width: size, height: size)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }

    private func draw(_ g: inout GraphicsContext, size sz: CGSize, t: Double, blips: [Blip]) {
        let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
        let r = min(sz.width, sz.height) / 2 - 2
        let period = scanning ? 1.4 : 4.2
        let sweep = (t.truncatingRemainder(dividingBy: period) / period) * 2 * .pi

        // Disc
        let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        g.fill(disc, with: .radialGradient(Gradient(colors: [accent.opacity(0.10), Theme.void.opacity(0.0)]), center: c, startRadius: 0, endRadius: r))

        // Rings
        for (i, f) in [0.42, 0.66, 0.88, 1.0].enumerated() {
            let rr = r * f
            let ring = Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
            g.stroke(ring, with: .color(accent.opacity(i == 3 ? 0.35 : 0.12)), style: StrokeStyle(lineWidth: i == 3 ? 1 : 0.7, dash: i == 3 ? [] : [2, 4]))
        }
        // Crosshair and ticks
        var cross = Path()
        cross.move(to: CGPoint(x: c.x - r, y: c.y)); cross.addLine(to: CGPoint(x: c.x + r, y: c.y))
        cross.move(to: CGPoint(x: c.x, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x, y: c.y + r))
        g.stroke(cross, with: .color(accent.opacity(0.08)), lineWidth: 0.6)
        var ticks = Path()
        for k in 0..<72 {
            let a = Double(k) / 72 * 2 * .pi
            let inner = r - (k % 6 == 0 ? 5 : 2.5)
            ticks.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
            ticks.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
        }
        g.stroke(ticks, with: .color(accent.opacity(0.3)), lineWidth: 0.6)

        // Sweep wedge with a fading tail
        let tail = 1.1
        let steps = 28
        for s in 0..<steps {
            let a0 = sweep - tail * Double(s) / Double(steps)
            let a1 = sweep - tail * Double(s + 1) / Double(steps)
            var wedge = Path()
            wedge.move(to: c)
            wedge.addArc(center: c, radius: r, startAngle: .radians(a1), endAngle: .radians(a0), clockwise: false)
            wedge.closeSubpath()
            let alpha = 0.22 * pow(1 - Double(s) / Double(steps), 2.2)
            g.fill(wedge, with: .color(accent.opacity(alpha)))
        }
        var beam = Path()
        beam.move(to: c)
        beam.addLine(to: CGPoint(x: c.x + cos(sweep) * r, y: c.y + sin(sweep) * r))
        g.stroke(beam, with: .color(accent.opacity(0.9)), lineWidth: 1.2)

        // Blips
        for b in blips {
            let p = CGPoint(x: c.x + cos(b.angle) * r * b.radius, y: c.y + sin(b.angle) * r * b.radius)
            var behind = sweep - b.angle
            behind = behind.truncatingRemainder(dividingBy: 2 * .pi)
            if behind < 0 { behind += 2 * .pi }
            let lit = max(0, 1 - behind / 2.4)
            let color: Color = b.health.isProblem ? b.health.color : (b.health == .operational ? accent : b.health.color)

            if b.health.isProblem {
                let phase = (t * 0.8 + b.angle).truncatingRemainder(dividingBy: 1)
                let pr = 3 + phase * 11
                g.stroke(Path(ellipseIn: CGRect(x: p.x - pr, y: p.y - pr, width: pr * 2, height: pr * 2)),
                         with: .color(color.opacity(0.8 * (1 - phase))), lineWidth: 1)
            }
            let base = b.health.isProblem ? 1.0 : 0.35 + 0.65 * lit
            let glowR = 2 + 5 * (b.health.isProblem ? 1 : lit)
            g.fill(Path(ellipseIn: CGRect(x: p.x - glowR, y: p.y - glowR, width: glowR * 2, height: glowR * 2)),
                   with: .radialGradient(Gradient(colors: [color.opacity(0.55 * base), .clear]), center: p, startRadius: 0, endRadius: glowR))
            let dot = b.health.isProblem ? 2.6 : 1.9
            g.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)), with: .color(color.opacity(base)))
        }

        // Core
        let core = Path(ellipseIn: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5))
        g.fill(core, with: .color(accent))
    }
}
