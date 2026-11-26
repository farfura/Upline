import AppKit
import SwiftUI

struct ServicesList: View {
    @Environment(Store.self) private var store
    let open: (String) -> Void

    var body: some View {
        let all = store.watched
        let problems = all.filter { $0.state.health.isProblem }
        let rest = all.filter { !$0.state.health.isProblem }
        let hot = rest.filter { $0.tier == .active }
        let idle = rest.filter { $0.tier == .idle }
        let dormant = rest.filter { $0.tier == .stale }

        LazyVStack(alignment: .leading, spacing: 6) {
            if all.isEmpty {
                EmptyState(
                    symbol: store.isScanning ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
                    title: store.isScanning ? "Scanning your projects" : "Nothing to watch yet",
                    message: store.isScanning ? "Looking for the services your code depends on." : "Add your code folders in Settings, then rescan."
                )
            }
            section("Attention", problems, color: Theme.red)
            section("Hot projects", hot, color: Theme.cyan)
            section("Idle", idle, color: Theme.secondary)
            section("Dormant", dormant, color: Theme.tertiary)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: all.map { "\($0.id)\($0.state.health.rawValue)" })
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [WatchedService], color: Color) -> some View {
        if !items.isEmpty {
            HStack {
                HUDLabel(title, color: color)
                Spacer()
                Text("\(items.count)").font(Theme.mono(9, .semibold)).foregroundStyle(Theme.tertiary)
            }
            .padding(.top, 10)
            .padding(.bottom, 2)
            ForEach(items) { s in
                ServiceRow(service: s) { open(s.id) }
                    .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
            }
        }
    }
}

struct ServiceRow: View {
    let service: WatchedService
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let h = service.state.health
        Button(action: action) {
            HStack(spacing: 11) {
                Monogram(entry: service.entry, size: 32, health: h)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(service.entry.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        if !service.regions.isEmpty {
                            TagChip(text: service.regions.first!.uppercased(), color: Theme.blue)
                        }
                        if service.state.auth != nil {
                            Image(systemName: "key.fill").font(.system(size: 8)).foregroundStyle(service.state.auth?.isProblem == true ? Theme.amber : Theme.mint)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(h.isProblem ? h.color.opacity(0.9) : Theme.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    StatusChip(health: h)
                    HStack(spacing: 6) {
                        Sparkline(samples: service.state.samples, color: h.isProblem ? h.color : Theme.cyan)
                            .frame(width: 54, height: 14)
                        Text(service.state.lastLatency.map { "\(Int($0))ms" } ?? "...")
                            .font(Theme.mono(9, .medium))
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hover ? Color.white.opacity(0.05) : Color.white.opacity(0.022))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(h.isProblem ? h.color.opacity(0.45) : (hover ? Theme.cyan.opacity(0.3) : Theme.hairline), lineWidth: 0.8)
                    )
            }
            .overlay(alignment: .leading) {
                if h.isProblem {
                    Capsule().fill(h.color).frame(width: 2.5, height: 24).glow(h.color, radius: 6).offset(x: -1)
                }
            }
            .shadow(color: h.isProblem ? h.color.opacity(0.18) : .clear, radius: 10)
            .scaleEffect(hover ? 1.01 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.snappy(duration: 0.18), value: hover)
    }

    private var subtitle: String {
        let h = service.state.health
        if h.isProblem {
            var s = service.reason
            if let since = service.state.since { s = "Since \(since.formatted(date: .omitted, time: .shortened)) · " + s }
            return s
        }
        let n = service.projects.count
        if service.entry.id.hasPrefix("custom:") { return "Manual endpoint" }
        let names = service.projects.prefix(2).map(\.name).joined(separator: ", ")
        return n > 2 ? "\(names) +\(n - 2)" : (names.isEmpty ? service.reason : names)
    }
}

struct ProjectsList: View {
    @Environment(Store.self) private var store
    let open: (String) -> Void

    var body: some View {
        let ignored = store.config.ignoredProjects
        let projects = store.projects
            .filter { !ignored.contains($0.path) }
            .sorted { a, b in
                let ta = store.tier(of: a), tb = store.tier(of: b)
                if ta != tb { return ta > tb }
                return (a.lastActivity ?? .distantPast) > (b.lastActivity ?? .distantPast)
            }
        LazyVStack(spacing: 8) {
            if projects.isEmpty {
                EmptyState(symbol: "folder.badge.questionmark", title: "No projects found",
                           message: "Point Upline at the folders where your code lives.")
            }
            ForEach(projects) { p in
                ProjectCard(project: p) { open(p.path) }
            }
        }
        .padding(.top, 6)
    }
}

struct ProjectCard: View {
    @Environment(Store.self) private var store
    let project: Project
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let tier = store.tier(of: project)
        let pinned = store.config.pinnedProjects.contains(project.path)
        let services = serviceStates
        let worst = services.map(\.health).max() ?? .operational

        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(tier.color)
                        .glow(tier.color, radius: tier == .active ? 5 : 0, opacity: 0.6)
                    Text(project.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    TagChip(text: pinned ? "PINNED" : tier.label, color: pinned ? Theme.violet : tier.color)
                    Spacer()
                    if worst.isProblem { StatusChip(health: worst) }
                    Button {
                        store.togglePin(project)
                    } label: {
                        Image(systemName: pinned ? "pin.fill" : "pin")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(pinned ? Theme.violet : Theme.tertiary)
                            .rotationEffect(.degrees(45))
                    }
                    .buttonStyle(.plain)
                    .help(pinned ? "Unpin: alerts follow activity" : "Pin: always alert for this project")
                }
                HStack(spacing: 6) {
                    Text(project.path.abbreviatingHome)
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    ForEach(project.stack.prefix(3), id: \.self) { TagChip(text: $0) }
                }
                HStack(spacing: 4) {
                    ForEach(services.prefix(16)) { dep in
                        ServiceDot(entry: dep.entry, health: dep.health)
                    }
                    if services.count > 16 {
                        Text("+\(services.count - 16)").font(Theme.mono(9, .semibold)).foregroundStyle(Theme.tertiary)
                    }
                    Spacer()
                    Text("\(services.count) deps").font(Theme.mono(9, .semibold)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(12)
            .glassCard(radius: 14, tint: worst.isProblem ? worst.color : (tier == .active ? Theme.cyan : .white), lit: hover || worst.isProblem)
            .scaleEffect(hover ? 1.01 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.snappy(duration: 0.18), value: hover)
    }

    private var serviceStates: [DepState] {
        let muted = store.config.projectMuted[project.path] ?? []
        return project.detections
            .filter { !muted.contains($0.serviceID) && !store.config.mutedServices.contains($0.serviceID) }
            .compactMap { d -> DepState? in
                guard let e = store.entry(for: d.serviceID) else { return nil }
                return DepState(entry: e, health: store.states[d.serviceID]?.health ?? .unknown)
            }
            .sorted { $0.health > $1.health }
    }
}

struct DepState: Identifiable {
    let entry: CatalogEntry
    let health: Health
    var id: String { entry.id }
}

struct ServiceDot: View {
    let entry: CatalogEntry
    let health: Health
    var body: some View {
        Text(entry.monogram)
            .font(.system(size: 7.5, weight: .bold, design: .rounded))
            .foregroundStyle(health.isProblem ? Theme.void : Color(hex: entry.color))
            .frame(width: 17, height: 17)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(health.isProblem ? health.color : Color(hex: entry.color).opacity(0.12))
            )
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder((health.isProblem ? health.color : Color(hex: entry.color)).opacity(0.4), lineWidth: 0.6))
            .shadow(color: health.isProblem ? health.color.opacity(0.7) : .clear, radius: 4)
            .help("\(entry.name): \(health.label)")
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.cyan)
                .glow(Theme.cyan, radius: 10)
                .symbolEffect(.pulse)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            Text(message).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
