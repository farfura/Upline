import AppKit
import Charts
import SwiftUI

struct ServiceDetailView: View {
    @Environment(Store.self) private var store
    let serviceID: String
    let back: () -> Void
    let openProject: (String) -> Void

    var body: some View {
        if let service = store.watched.first(where: { $0.id == serviceID }) {
            content(service)
        } else {
            VStack {
                DetailTopBar(title: "Service", back: back)
                EmptyState(symbol: "eye.slash", title: "Not watched", message: "This service was muted or removed.")
                Spacer()
            }
        }
    }

    private func content(_ s: WatchedService) -> some View {
        let h = s.state.health
        return VStack(spacing: 0) {
            DetailTopBar(title: s.entry.category.title, back: back)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(s)
                    statTiles(s)
                    latencyChart(s)
                    if s.entry.auth != nil { deepCheck(s) }
                    if let o = s.state.official, !o.incidents.isEmpty { incidents(o) }
                    if let o = s.state.official, !o.components.isEmpty { components(s, o) }
                    usedBy(s)
                    actions(s)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.never)
        }
        .overlay(alignment: .top) {
            if h.isProblem {
                LinearGradient(colors: [h.color.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 180).allowsHitTesting(false)
            }
        }
    }

    // MARK: Sections

    private func header(_ s: WatchedService) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Monogram(entry: s.entry, size: 52, health: s.state.health)
                .glow(Color(hex: s.entry.color), radius: 14, opacity: 0.35)
            VStack(alignment: .leading, spacing: 6) {
                Text(s.entry.name)
                    .font(.system(size: 20, weight: .bold)).fontWidth(.expanded)
                    .foregroundStyle(Theme.text)
                StatusChip(health: s.state.health, large: true)
                Text(s.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(s.state.health.isProblem ? s.state.health.color : Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !s.regions.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "globe.europe.africa").font(.system(size: 9)).foregroundStyle(Theme.blue)
                        ForEach(s.regions, id: \.self) { TagChip(text: $0.uppercased(), color: Theme.blue) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func statTiles(_ s: WatchedService) -> some View {
        let st = s.state
        return HStack(spacing: 8) {
            Tile(label: "Latency", value: st.lastLatency.map { "\(Int($0))" } ?? "...", unit: "ms", color: Theme.cyan)
            Tile(label: "Uptime", value: st.uptimeRatio.map { String(format: "%.1f", $0 * 100) } ?? "...", unit: "%", color: (st.uptimeRatio ?? 1) < 0.98 ? Theme.amber : Theme.mint)
            Tile(label: "Probes", value: "\(st.samples.count)", unit: "", color: Theme.violet)
            Tile(label: st.since == nil ? "Feed" : "Since", value: st.since.map { $0.formatted(date: .omitted, time: .shortened) } ?? feedLabel(st), unit: "", color: Theme.blue)
        }
    }

    private func feedLabel(_ st: ServiceState) -> String {
        guard let o = st.official else { return st.officialError == nil ? "PROBE" : "NONE" }
        switch o.source {
        case .statuspage: return "LIVE"
        case .instatus, .statusio: return "LIVE"
        case .feed: return "RSS"
        }
    }

    private func latencyChart(_ s: WatchedService) -> some View {
        let samples = s.state.samples
        let color = s.state.health.isProblem ? s.state.health.color : Theme.cyan
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                HUDLabel("Live probe")
                Spacer()
                Text(s.state.samples.last?.detail ?? "Waiting").font(Theme.mono(9)).foregroundStyle(Theme.tertiary)
            }
            if samples.count < 2 {
                ZStack {
                    Sparkline(samples: samples, color: color)
                    Text("Collecting samples").font(Theme.mono(9.5)).foregroundStyle(Theme.tertiary)
                }
                .frame(height: 84)
            } else {
                Chart {
                    ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                        if let ms = sample.latencyMs, sample.ok {
                            AreaMark(x: .value("Time", sample.date), y: .value("ms", ms))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("Time", sample.date), y: .value("ms", ms))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(color)
                                .lineStyle(StrokeStyle(lineWidth: 1.6))
                        } else {
                            RuleMark(x: .value("Time", sample.date))
                                .foregroundStyle(Theme.red.opacity(0.7))
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel(format: .dateTime.hour().minute()).font(Theme.mono(8)).foregroundStyle(Theme.tertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel().font(Theme.mono(8)).foregroundStyle(Theme.tertiary)
                    }
                }
                .frame(height: 96)
            }
        }
        .padding(12)
        .glassCard(radius: 14, tint: color)
    }

    private func deepCheck(_ s: WatchedService) -> some View {
        let on = store.config.deepChecks.contains(s.id)
        let host = s.entry.auth.flatMap { URL(string: $0.url)?.host } ?? "the service"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                HUDLabel("Deep check", color: on ? Theme.violet : Theme.tertiary)
                Spacer()
                Toggle("", isOn: Binding(get: { on }, set: { store.setDeepCheck(s.id, on: $0) }))
                    .toggleStyle(.switch).controlSize(.mini).tint(Theme.violet).labelsHidden()
            }
            Text("Checks that your own key works, not just that the API is up. It catches revoked keys, rate limits and empty credit. The key is read from your project's .env when the check runs, kept in memory and sent only to \(host).")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if on {
                HStack(spacing: 8) {
                    let auth = s.state.auth
                    Image(systemName: auth == nil ? "hourglass" : (auth!.isProblem ? "key.slash" : "key.fill"))
                        .foregroundStyle(auth?.isProblem == true ? Theme.amber : Theme.mint)
                    Text(auth?.label ?? "Running first check").font(Theme.mono(10.5, .semibold))
                        .foregroundStyle(auth?.isProblem == true ? Theme.amber : Theme.text)
                    Spacer()
                    Text("ENV: \(s.entry.auth?.envKeys.first ?? "")").font(Theme.mono(8.5)).foregroundStyle(Theme.tertiary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
            }
        }
        .padding(12)
        .glassCard(radius: 14, tint: Theme.violet, lit: on)
    }

    private func incidents(_ o: OfficialStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDLabel("Incident log", color: Theme.orange)
            ForEach(o.incidents) { inc in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        GlowDot(color: inc.impact.color, size: 7, pulsing: !inc.isMaintenance)
                            .padding(.top, 4)
                        Rectangle().fill(LinearGradient(colors: [inc.impact.color.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                            .frame(width: 1)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(inc.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            TagChip(text: inc.status.uppercased().replacingOccurrences(of: "_", with: " "), color: inc.impact.color)
                            Text("Started \(inc.createdAt.formatted(date: .omitted, time: .shortened)) · updated \(inc.updatedAt.shortAgo)")
                                .font(Theme.mono(8.5)).foregroundStyle(Theme.tertiary)
                        }
                        ForEach(Array(inc.updates.prefix(3).enumerated()), id: \.offset) { _, u in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(u.status.uppercased()) · \(u.date.formatted(date: .omitted, time: .shortened))")
                                    .font(Theme.mono(8, .semibold)).foregroundStyle(Theme.secondary)
                                Text(u.body).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                    .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 2)
                        }
                        if let link = inc.link {
                            Link(destination: link) {
                                Text("Open incident ↗").font(Theme.mono(9.5, .semibold)).foregroundStyle(Theme.cyan)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .glassCard(radius: 14, tint: Theme.orange, lit: true)
    }

    private func components(_ s: WatchedService, _ o: OfficialStatus) -> some View {
        let selection = store.config.componentSelections[s.id] ?? []
        let relevant = Set(Store.relevantComponents(o.components, selection: selection, regions: s.regions).map(\.id))
        let mode = !selection.isEmpty ? "Your pick" : (s.regions.isEmpty ? "All components" : "Auto by region")
        let sorted = o.components.sorted { a, b in
            let ra = relevant.contains(a.id), rb = relevant.contains(b.id)
            if ra != rb { return ra }
            if a.health != b.health { return a.health > b.health }
            return a.name < b.name
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                HUDLabel("Components")
                Spacer()
                Text("\(relevant.count)/\(o.components.count) · \(mode.uppercased())")
                    .font(Theme.mono(8.5, .semibold)).foregroundStyle(Theme.tertiary)
            }
            Text("Only the components you watch can raise an alert. Tick the ones your project really uses.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
            ComponentGrid(components: sorted, relevant: relevant) { comp in
                store.toggleComponent(s.id, componentID: comp.id, all: o.components)
            }
        }
        .padding(12)
        .glassCard(radius: 14)
    }

    private func usedBy(_ s: WatchedService) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HUDLabel("Used by")
            if s.projects.isEmpty {
                Text("Added by hand in Settings.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            ForEach(s.projects) { p in
                let tier = store.tier(of: p)
                let evidence = p.detections.first { $0.serviceID == s.id }?.evidence ?? []
                Button { openProject(p.path) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(tier.color).frame(width: 6, height: 6).glow(tier.color, radius: 3).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(p.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                                TagChip(text: tier.label, color: tier.color)
                            }
                            Text(evidence.prefix(2).joined(separator: "   ")).font(Theme.mono(8.5)).foregroundStyle(Theme.tertiary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary).padding(.top, 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Stop watching \(s.entry.name) in \(p.name)") { store.setMuted(s.id, in: p, muted: true) }
                }
            }
        }
        .padding(12)
        .glassCard(radius: 14)
    }

    private func actions(_ s: WatchedService) -> some View {
        HStack(spacing: 8) {
            if let page = s.state.official?.pageURL ?? s.entry.statusPage.flatMap(URL.init(string:)) {
                NeonButton(title: "Status page", symbol: "arrow.up.right", prominent: true) { NSWorkspace.shared.open(page) }
            }
            NeonButton(title: "Probe now", symbol: "bolt.fill", color: Theme.cyan, prominent: false) { store.refreshNow() }
            Spacer()
            NeonButton(title: "Mute", symbol: "bell.slash", color: Theme.red, prominent: false) {
                store.setMuted(s.id, muted: true)
                back()
            }
        }
    }
}

struct Tile: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(Theme.mono(8, .semibold)).tracking(1.2).foregroundStyle(Theme.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(Theme.mono(15, .bold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(unit).font(Theme.mono(9, .medium)).foregroundStyle(color.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassCard(radius: 11, tint: color)
    }
}

struct ComponentGrid: View {
    let components: [Component]
    let relevant: Set<String>
    let toggle: (Component) -> Void
    @State private var expanded = false

    var body: some View {
        let shown = expanded ? components : Array(components.prefix(8))
        VStack(spacing: 4) {
            ForEach(shown) { c in
                let on = relevant.contains(c.id)
                Button { toggle(c) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: on ? "checkmark.square.fill" : "square")
                            .font(.system(size: 11))
                            .foregroundStyle(on ? Theme.cyan : Theme.tertiary)
                        Text(c.name).font(.system(size: 11)).foregroundStyle(on ? Theme.text : Theme.tertiary).lineLimit(1)
                        if let g = c.groupName {
                            Text(g).font(Theme.mono(8)).foregroundStyle(Theme.tertiary).lineLimit(1)
                        }
                        Spacer()
                        GlowDot(color: c.health.color, size: 5)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if components.count > 8 {
                Button(expanded ? "Show less" : "Show all \(components.count)") {
                    withAnimation(.snappy) { expanded.toggle() }
                }
                .buttonStyle(.plain)
                .font(Theme.mono(9.5, .semibold))
                .foregroundStyle(Theme.cyan)
                .padding(.top, 4)
            }
        }
    }
}

struct DetailTopBar: View {
    let title: String
    let back: () -> Void
    @State private var hover = false

    var body: some View {
        HStack {
            Button(action: back) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text("BACK").font(Theme.mono(9.5, .bold)).tracking(1.4)
                }
                .foregroundStyle(hover ? Theme.cyan : Theme.secondary)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(hover ? 0.07 : 0.03)).overlay(Capsule().strokeBorder(Theme.hairline)))
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            Spacer()
            HUDLabel(title)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}
