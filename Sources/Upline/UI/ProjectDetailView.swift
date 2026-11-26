import AppKit
import SwiftUI

struct ProjectDetailView: View {
    @Environment(Store.self) private var store
    let path: String
    let back: () -> Void
    let openService: (String) -> Void
    @State private var showAdd = false

    var body: some View {
        if let project = store.projects.first(where: { $0.path == path }) {
            content(project)
        } else {
            VStack {
                DetailTopBar(title: "Project", back: back)
                EmptyState(symbol: "folder.badge.questionmark", title: "Project gone", message: "It wasn't found in the last scan.")
                Spacer()
            }
        }
    }

    private func content(_ p: Project) -> some View {
        let tier = store.tier(of: p)
        let pinned = store.config.pinnedProjects.contains(p.path)
        let muted = store.config.projectMuted[p.path] ?? []
        let detections = p.detections.sorted { a, b in
            let ha = store.states[a.serviceID]?.health ?? .unknown
            let hb = store.states[b.serviceID]?.health ?? .unknown
            if ha != hb { return ha > hb }
            return (store.entry(for: a.serviceID)?.name ?? "") < (store.entry(for: b.serviceID)?.name ?? "")
        }
        let live = detections.filter { !muted.contains($0.serviceID) }
        let worst = live.compactMap { store.states[$0.serviceID]?.health }.max() ?? .operational

        return VStack(spacing: 0) {
            DetailTopBar(title: "Project", back: back)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill").font(.system(size: 22)).foregroundStyle(tier.color).glow(tier.color, radius: 8)
                            Text(p.name).font(.system(size: 20, weight: .bold)).fontWidth(.expanded).foregroundStyle(Theme.text).lineLimit(1)
                        }
                        Text(p.path.abbreviatingHome).font(Theme.mono(10)).foregroundStyle(Theme.tertiary).textSelection(.enabled)
                        HStack(spacing: 6) {
                            TagChip(text: pinned ? "PINNED" : tier.label, color: pinned ? Theme.violet : tier.color)
                            ForEach(p.stack, id: \.self) { TagChip(text: $0) }
                        }
                        Text(canWorkLine(worst: worst, live: live.count))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(worst.isProblem ? worst.color : Theme.mint)
                            .padding(.top, 2)
                    }

                    HStack(spacing: 8) {
                        NeonButton(title: pinned ? "Unpin" : "Pin alerts", symbol: pinned ? "pin.slash" : "pin.fill", color: Theme.violet, prominent: !pinned) {
                            store.togglePin(p)
                        }
                        NeonButton(title: "Reveal", symbol: "folder", color: Theme.cyan, prominent: false) {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: p.path)
                        }
                        Spacer()
                        NeonButton(title: "Ignore", symbol: "eye.slash", color: Theme.red, prominent: false) {
                            store.toggleIgnore(p)
                            back()
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            HUDLabel("Dependencies")
                            Spacer()
                            Text("\(live.count) WATCHED · \(muted.count) MUTED").font(Theme.mono(8.5, .semibold)).foregroundStyle(Theme.tertiary)
                        }
                        ForEach(detections, id: \.serviceID) { d in
                            if let entry = store.entry(for: d.serviceID) {
                                DependencyRow(
                                    entry: entry, detection: d,
                                    health: store.states[d.serviceID]?.health ?? .unknown,
                                    muted: muted.contains(d.serviceID) || store.config.mutedServices.contains(d.serviceID),
                                    toggle: { on in store.setMuted(d.serviceID, in: p, muted: !on) },
                                    open: { openService(d.serviceID) }
                                )
                            }
                        }
                    }
                    .padding(12)
                    .glassCard(radius: 14)

                    Text("Upline reads package files, env variable names, hosts in env URLs and code, and git remotes. Secret values are never stored.")
                        .font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.never)
        }
    }

    private func canWorkLine(worst: Health, live: Int) -> String {
        if live == 0 { return "No dependencies watched." }
        switch worst {
        case .operational, .maintenance: return "Clear to work. All \(live) dependencies answering."
        case .unknown: return "Still collecting signals."
        case .suspected: return "Something looks off. Expect flaky behaviour."
        default: return "Blocked upstream. Don't debug your own code yet."
        }
    }
}

struct DependencyRow: View {
    let entry: CatalogEntry
    let detection: Detection
    let health: Health
    let muted: Bool
    let toggle: (Bool) -> Void
    let open: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Monogram(entry: entry, size: 24, health: muted ? .operational : health)
                    .opacity(muted ? 0.4 : 1)
                Button(action: open) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name).font(.system(size: 12, weight: .medium)).foregroundStyle(muted ? Theme.tertiary : Theme.text)
                        Text("\(detection.evidence.count) signal\(detection.evidence.count == 1 ? "" : "s")\(detection.regions.isEmpty ? "" : " · " + detection.regions.joined(separator: ", "))")
                            .font(Theme.mono(8.5)).foregroundStyle(Theme.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(muted)
                Spacer()
                if !muted { StatusChip(health: health) }
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .buttonStyle(.plain)
                Toggle("", isOn: Binding(get: { !muted }, set: toggle))
                    .toggleStyle(.switch).controlSize(.mini).tint(Theme.cyan).labelsHidden()
            }
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(detection.evidence, id: \.self) { e in
                        Text("▸ " + e).font(Theme.mono(8.5)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    ForEach(detection.hosts, id: \.self) { h in
                        Text("◉ probe " + h).font(Theme.mono(8.5)).foregroundStyle(Theme.cyan.opacity(0.8)).lineLimit(1)
                    }
                }
                .padding(.leading, 34)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }
}
