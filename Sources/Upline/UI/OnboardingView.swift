import AppKit
import SwiftUI

struct OnboardingView: View {
    enum Step { case intro, scanning, results }

    @Environment(Store.self) private var store
    @State private var step: Step = .intro
    let close: () -> Void

    var body: some View {
        ZStack {
            SpaceBackground(intensity: 1.4)
            Group {
                switch step {
                case .intro: intro
                case .scanning: scanning
                case .results: results
                }
            }
            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97)), removal: .opacity))
        }
        .frame(width: 780, height: 540)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: step)
        .onChange(of: store.isScanning) { _, scanning in
            if !scanning && step == .scanning {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    step = .results
                }
            }
        }
    }

    // MARK: Intro

    private var intro: some View {
        HStack(spacing: 40) {
            RadarView(services: [], size: 260, scanning: false)
                .overlay {
                    Circle().strokeBorder(Theme.cyan.opacity(0.15), lineWidth: 1).frame(width: 300, height: 300)
                }
            VStack(alignment: .leading, spacing: 18) {
                HUDLabel("Upline · first contact", color: Theme.cyan)
                Text("KNOW IT'S\nTHEM BEFORE\nYOU DEBUG.")
                    .font(.system(size: 34, weight: .heavy)).fontWidth(.expanded)
                    .foregroundStyle(LinearGradient(colors: [Theme.text, Theme.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .lineSpacing(-2)
                Text("Upline scans your repos for every third party they depend on, then watches status pages and the real API hosts. When something breaks, you hear about it first, with the projects it affects.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    HUDLabel("Scan these folders")
                    FolderChips()
                }
                HStack(spacing: 10) {
                    NeonButton(title: "Scan my projects", symbol: "dot.radiowaves.left.and.right") {
                        step = .scanning
                        Task { await store.rescan() }
                    }
                    .disabled(store.config.roots.isEmpty)
                    Text("Reads package files, env key names and hosts. Never secret values.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
                }
            }
            .frame(width: 400)
        }
        .padding(40)
    }

    // MARK: Scanning

    private var scanning: some View {
        let s = store.scan
        let progress = s.reposFound == 0 ? 0 : Double(s.reposScanned) / Double(s.reposFound)
        return HStack(spacing: 44) {
            ZStack {
                RadarView(services: store.watched, size: 280, scanning: true)
                VStack(spacing: 2) {
                    Text("\(Int(progress * 100))%")
                        .font(Theme.mono(26, .bold)).foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                        .shadow(color: Theme.cyan, radius: 10)
                    Text("SCANNING").font(Theme.mono(9, .bold)).tracking(2.4).foregroundStyle(Theme.cyan)
                }
                .padding(14)
                .background(Circle().fill(Theme.void.opacity(0.7)))
            }
            VStack(alignment: .leading, spacing: 20) {
                HUDLabel("Mapping your stack", color: Theme.cyan)
                HStack(spacing: 28) {
                    BigCounter(value: s.reposFound, label: "Repos found")
                    BigCounter(value: s.reposScanned, label: "Scanned")
                    BigCounter(value: s.servicesFound, label: "Services", color: Theme.cyan)
                }
                GlowProgress(value: progress)
                Text(s.currentPath.isEmpty ? "Locating repositories..." : s.currentPath)
                    .font(Theme.mono(10.5)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                VStack(alignment: .leading, spacing: 6) {
                    HUDLabel("Contacts")
                    ForEach(s.lastHits, id: \.self) { name in
                        HStack(spacing: 8) {
                            GlowDot(color: Theme.mint, size: 5)
                            Text(name).font(Theme.mono(11, .semibold)).foregroundStyle(Theme.text)
                            Text("LOCKED").font(Theme.mono(8, .bold)).tracking(1.4).foregroundStyle(Theme.mint.opacity(0.7))
                        }
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: s.lastHits)
                .frame(height: 150, alignment: .top)
            }
            .frame(width: 360)
        }
        .padding(40)
    }

    // MARK: Results

    private var results: some View {
        let watched = store.watched
        let projectCount = store.projects.filter { !store.config.ignoredProjects.contains($0.path) }.count
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    HUDLabel("Scan complete", color: Theme.mint)
                    Text("Found \(projectCount) projects using \(watched.count) services.")
                        .font(.system(size: 24, weight: .heavy)).fontWidth(.expanded)
                        .foregroundStyle(LinearGradient(colors: [Theme.text, Theme.cyan], startPoint: .leading, endPoint: .trailing))
                    Text("Untick anything you don't care about. You can change this any time.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
                    ForEach(allDetected(), id: \.entry.id) { item in
                        ServiceToggleChip(entry: item.entry, count: item.count, on: !store.config.mutedServices.contains(item.entry.id)) {
                            store.setMuted(item.entry.id, muted: !store.config.mutedServices.contains(item.entry.id))
                        }
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.never)
            HStack {
                NeonButton(title: "Rescan", symbol: "arrow.clockwise", prominent: false) {
                    step = .scanning
                    Task { await store.rescan() }
                }
                Spacer()
                Text("Upline lives in your menu bar. Look for the radar.")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                NeonButton(title: "Start watching", symbol: "antenna.radiowaves.left.and.right") {
                    store.completeOnboarding()
                    close()
                }
            }
        }
        .padding(36)
    }

    private struct Item { let entry: CatalogEntry; let count: Int }

    private func allDetected() -> [Item] {
        var counts: [String: Int] = [:]
        for p in store.projects where !store.config.ignoredProjects.contains(p.path) {
            for d in p.detections { counts[d.serviceID, default: 0] += 1 }
        }
        return counts.compactMap { id, n in store.entry(for: id).map { Item(entry: $0, count: n) } }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.entry.name < $1.entry.name }
    }
}

struct BigCounter: View {
    let value: Int
    let label: String
    var color: Color = Theme.text
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(Theme.mono(30, .bold))
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy, value: value)
            Text(label.uppercased()).font(Theme.mono(8.5, .semibold)).tracking(1.4).foregroundStyle(Theme.tertiary)
        }
    }
}

struct GlowProgress: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.violet, Theme.cyan], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * value))
                    .shadow(color: Theme.cyan.opacity(0.8), radius: 6)
                    .animation(.spring(response: 0.5), value: value)
            }
        }
        .frame(height: 4)
    }
}

struct ServiceToggleChip: View {
    let entry: CatalogEntry
    let count: Int
    let on: Bool
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Monogram(entry: entry, size: 24)
                    .saturation(on ? 1 : 0)
                    .opacity(on ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(on ? Theme.text : Theme.tertiary).lineLimit(1)
                    Text("\(count) project\(count == 1 ? "" : "s") · \(entry.category.title)").font(Theme.mono(8.5)).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Theme.cyan : Theme.tertiary)
            }
            .padding(9)
            .glassCard(radius: 11, tint: on ? Color(hex: entry.color) : .white, lit: on && hover)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct FolderChips: View {
    @Environment(Store.self) private var store

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(store.config.roots, id: \.self) { root in
                HStack(spacing: 5) {
                    Image(systemName: "folder").font(.system(size: 9))
                    Text(root.abbreviatingHome).font(Theme.mono(10, .medium))
                    Button {
                        store.mutate { $0.roots.removeAll { $0 == root } }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 7.5, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(Theme.cyan)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Theme.cyan.opacity(0.08)).overlay(Capsule().strokeBorder(Theme.cyan.opacity(0.3), lineWidth: 0.7)))
            }
            Button {
                if let path = pickFolder() {
                    store.mutate { if !$0.roots.contains(path) { $0.roots.append(path) } }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                    Text("Add folder").font(Theme.mono(10, .semibold))
                }
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            }
            .buttonStyle(.plain)
        }
    }
}

@MainActor
func pickFolder() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Watch this folder"
    panel.message = "Choose a folder that contains your git repositories"
    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return url.path.abbreviatingHome
}

/// Wraps chips onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
