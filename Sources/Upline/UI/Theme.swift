import AppKit
import SwiftUI

enum Theme {
    static let void = Color(hex: "#04060B")
    static let deep = Color(hex: "#080C16")
    static let panel = Color(hex: "#0D1322")
    static let raised = Color(hex: "#131B2E")

    static let text = Color(hex: "#E8F0FF")
    static let secondary = Color(hex: "#8E9AB6")
    static let tertiary = Color(hex: "#55607A")
    static let hairline = Color.white.opacity(0.07)

    static let cyan = Color(hex: "#4DF3FF")
    static let mint = Color(hex: "#3DFFA8")
    static let amber = Color(hex: "#FFC24D")
    static let orange = Color(hex: "#FF8A3D")
    static let red = Color(hex: "#FF4D6A")
    static let violet = Color(hex: "#8B7CFF")
    static let blue = Color(hex: "#6EA8FF")
    static let steel = Color(hex: "#6B7489")

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Health {
    var color: Color {
        switch self {
        case .operational: Theme.mint
        case .unknown: Theme.steel
        case .maintenance: Theme.blue
        case .suspected: Theme.amber
        case .degraded: Theme.amber
        case .partialOutage: Theme.orange
        case .majorOutage: Theme.red
        }
    }

    var symbol: String {
        switch self {
        case .operational: "checkmark"
        case .unknown: "questionmark"
        case .maintenance: "wrench.adjustable"
        case .suspected: "eye.trianglebadge.exclamationmark"
        case .degraded: "exclamationmark"
        case .partialOutage: "exclamationmark.2"
        case .majorOutage: "xmark"
        }
    }
}

extension ActivityTier {
    var color: Color {
        switch self {
        case .active: Theme.cyan
        case .idle: Theme.secondary
        case .stale: Theme.tertiary
        }
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b: Double
        if s.count == 6 {
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
        } else {
            r = 0.6; g = 0.6; b = 0.7
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - Surfaces

/// The deep space backdrop: an animated aurora mesh with a faint dot grid on top.
struct SpaceBackground: View {
    var intensity: Double = 1
    var tint: Color = Theme.cyan
    @State private var visible = false

    var body: some View {
        ZStack {
            Theme.void
            TimelineView(.animation(minimumInterval: 1 / 20, paused: !visible)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                aurora(t)
            }
            DotGrid().opacity(0.5)
            LinearGradient(colors: [.clear, Theme.void.opacity(0.85)], startPoint: .center, endPoint: .bottom)
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }

    @ViewBuilder
    private func aurora(_ t: Double) -> some View {
        if #available(macOS 15.0, *) {
            let w = Float(sin(t * 0.35) * 0.12)
            let v = Float(cos(t * 0.27) * 0.10)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5 + w, 0], [1, 0],
                    [0, 0.45 + v], [0.55 - w, 0.42 + v], [1, 0.5 - v],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    tint.opacity(0.22 * intensity), Theme.violet.opacity(0.18 * intensity), Theme.deep,
                    Theme.deep, Theme.panel, tint.opacity(0.08 * intensity),
                    Theme.void, Theme.void, Theme.void,
                ]
            )
        } else {
            RadialGradient(colors: [tint.opacity(0.18 * intensity), .clear], center: .topLeading, startRadius: 10, endRadius: 380)
        }
    }
}

struct DotGrid: View {
    var spacing: CGFloat = 14
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.1, height: 1.1)), with: .color(.white.opacity(0.06)))
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// A dark glass card with a lit top edge.
struct GlassCard: ViewModifier {
    var radius: CGFloat = 14
    var tint: Color = .white
    var lit: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.panel.opacity(0.75), Theme.deep.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [tint.opacity(lit ? 0.55 : 0.16), .white.opacity(0.03), tint.opacity(lit ? 0.18 : 0.05)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: lit ? tint.opacity(0.25) : .black.opacity(0.4), radius: lit ? 14 : 8, y: 4)
            }
    }
}

extension View {
    func glassCard(radius: CGFloat = 14, tint: Color = .white, lit: Bool = false) -> some View {
        modifier(GlassCard(radius: radius, tint: tint, lit: lit))
    }

    /// Liquid Glass on macOS 26 when built with Xcode 26, dark glass otherwise.
    @ViewBuilder
    func futureGlass(radius: CGFloat = 10, tint: Color? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(tint.map { Glass.regular.tint($0.opacity(0.35)).interactive() } ?? Glass.regular.interactive(),
                             in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self.glassCard(radius: radius, tint: tint ?? .white)
        }
        #else
        self.glassCard(radius: radius, tint: tint ?? .white)
        #endif
    }

    func glow(_ color: Color, radius: CGFloat = 6, opacity: Double = 0.8) -> some View {
        shadow(color: color.opacity(opacity), radius: radius)
    }
}

// MARK: - Small parts

struct HUDLabel: View {
    let text: String
    var color: Color = Theme.tertiary
    init(_ text: String, color: Color = Theme.tertiary) {
        self.text = text
        self.color = color
    }
    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(color.opacity(0.9)).frame(width: 6, height: 1.5)
            Text(text.uppercased())
                .font(Theme.mono(9.5, .semibold))
                .tracking(1.8)
                .foregroundStyle(color)
        }
    }
}

struct GlowDot: View {
    let color: Color
    var size: CGFloat = 7
    var pulsing = false
    @State private var on = false

    var body: some View {
        ZStack {
            if pulsing {
                Circle()
                    .stroke(color.opacity(on ? 0 : 0.7), lineWidth: 1.2)
                    .frame(width: size * (on ? 3.2 : 1), height: size * (on ? 3.2 : 1))
            }
            Circle().fill(color).frame(width: size, height: size)
                .shadow(color: color.opacity(0.9), radius: size * 0.7)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard pulsing else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { on = true }
        }
    }
}

struct StatusChip: View {
    let health: Health
    var large = false

    var body: some View {
        HStack(spacing: 5) {
            GlowDot(color: health.color, size: large ? 7 : 5, pulsing: health.isProblem)
            Text(health.shortLabel)
                .font(Theme.mono(large ? 10.5 : 8.5, .bold))
                .tracking(1.2)
                .foregroundStyle(health.color)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, large ? 10 : 7)
        .padding(.vertical, large ? 5 : 3)
        .background(
            Capsule().fill(health.color.opacity(0.10))
                .overlay(Capsule().strokeBorder(health.color.opacity(0.35), lineWidth: 0.8))
        )
        .animation(.snappy, value: health)
    }
}

struct Monogram: View {
    let entry: CatalogEntry
    var size: CGFloat = 30
    var health: Health = .operational

    var body: some View {
        let tint = Color(hex: entry.color)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(LinearGradient(colors: [tint.opacity(0.75), tint.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.9)
            if entry.isCustom {
                Image(systemName: entry.category.symbol)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(tint)
            } else {
                Text(entry.monogram)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.7), radius: 4)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if health.isProblem {
                Circle().fill(health.color).frame(width: size * 0.3, height: size * 0.3)
                    .overlay(Circle().stroke(Theme.void, lineWidth: 2))
                    .shadow(color: health.color, radius: 4)
                    .offset(x: 3, y: 3)
            }
        }
    }
}

/// A latency trace drawn on a Canvas. Failed probes show as red ticks.
struct Sparkline: View {
    let samples: [ProbeSample]
    var color: Color = Theme.cyan

    var body: some View {
        Canvas { ctx, size in
            let recent = Array(samples.suffix(30))
            guard recent.count >= 2 else {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height / 2))
                line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                ctx.stroke(line, with: .color(Theme.tertiary.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                return
            }
            let values = recent.map { $0.latencyMs ?? 0 }
            let maxV = max(values.max() ?? 1, 50)
            let step = size.width / CGFloat(recent.count - 1)
            func point(_ i: Int) -> CGPoint {
                let v = recent[i].latencyMs ?? maxV
                return CGPoint(x: CGFloat(i) * step, y: size.height - 2 - CGFloat(v / maxV) * (size.height - 4))
            }
            var path = Path()
            path.move(to: point(0))
            for i in 1..<recent.count {
                let p0 = point(i - 1), p1 = point(i)
                let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
                path.addQuadCurve(to: mid, control: p0)
                if i == recent.count - 1 { path.addLine(to: p1) }
            }
            var fill = path
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.28), color.opacity(0)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            for (i, s) in recent.enumerated() where !s.ok {
                let x = CGFloat(i) * step
                ctx.fill(Path(CGRect(x: x - 0.75, y: 1, width: 1.5, height: size.height - 2)), with: .color(Theme.red.opacity(0.85)))
            }
            let last = point(recent.count - 1)
            ctx.fill(Path(ellipseIn: CGRect(x: last.x - 2, y: last.y - 2, width: 4, height: 4)), with: .color(color))
        }
    }
}

struct IconButton: View {
    let symbol: String
    var help: String = ""
    var spinning = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(hover ? Theme.cyan : Theme.secondary)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: spinning)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hover ? Theme.cyan.opacity(0.10) : .white.opacity(0.03))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(hover ? Theme.cyan.opacity(0.4) : Theme.hairline))
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct NeonButton: View {
    let title: String
    var symbol: String? = nil
    var color: Color = Theme.cyan
    var prominent = true
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(prominent ? Theme.void : color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(color.opacity(hover ? 0.14 : 0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(color.opacity(prominent ? 0 : 0.4)))
            )
            .shadow(color: color.opacity(prominent ? (hover ? 0.6 : 0.35) : 0), radius: hover ? 14 : 8)
            .scaleEffect(hover ? 1.02 : 1)
            .animation(.snappy(duration: 0.2), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct TagChip: View {
    let text: String
    var color: Color = Theme.secondary
    var body: some View {
        Text(text)
            .font(Theme.mono(9, .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.22), lineWidth: 0.6))
    }
}

/// A thin cyan beam that sweeps across while a refresh is running.
struct ScanBeam: View {
    let active: Bool
    @State private var x: CGFloat = -0.3

    var body: some View {
        GeometryReader { geo in
            if active {
                LinearGradient(colors: [.clear, Theme.cyan.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.35, height: 1)
                    .offset(x: x * geo.size.width)
                    .shadow(color: Theme.cyan, radius: 4)
                    .onAppear {
                        x = -0.35
                        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) { x = 1 }
                    }
            }
        }
        .frame(height: 1)
        .allowsHitTesting(false)
    }
}

extension Date {
    var shortAgo: String {
        let s = Int(Date().timeIntervalSince(self))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }
}
