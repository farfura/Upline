import AppKit
import SwiftUI

enum Route: Equatable {
    case service(String)
    case project(String)
}

enum PanelTab: String, CaseIterable {
    case services = "Services"
    case projects = "Projects"
}

struct RootView: View {
    @Environment(Store.self) private var store
    @State private var route: Route?
    @State private var tab: PanelTab = .services
    @Namespace private var tabNS

    var body: some View {
        ZStack {
            SpaceBackground(intensity: store.overall.isProblem ? 1.3 : 1, tint: store.overall.isProblem ? store.overall.color : Theme.cyan)

            if !store.config.onboarded {
                WelcomeCard()
                    .transition(.opacity)
            } else if let route {
                Group {
                    switch route {
                    case .service(let id):
                        ServiceDetailView(serviceID: id, back: { go(nil) }, openProject: { go(.project($0)) })
                    case .project(let path):
                        ProjectDetailView(path: path, back: { go(nil) }, openService: { go(.service($0)) })
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
            } else {
                home.transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .frame(width: 420, height: 640)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: route)
        .background(KeyboardShortcuts(refresh: store.refreshNow, back: { go(nil) }))
    }

    private func go(_ r: Route?) { route = r }

    private var home: some View {
        VStack(spacing: 0) {
            HeaderBar()
            HeroPanel()
                .padding(.horizontal, 14)
                .padding(.top, 4)
            if let problem = store.network.problem {
                ItsYouBanner(text: problem)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            tabBar
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)
            ScrollView {
                Group {
                    switch tab {
                    case .services: ServicesList(open: { go(.service($0)) })
                    case .projects: ProjectsList(open: { go(.project($0)) })
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03), .init(color: .black, location: 0.94), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            FooterBar()
        }
        .animation(.snappy, value: store.network)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(PanelTab.allCases, id: \.self) { t in
                let count = t == .services ? store.watched.count : store.projects.filter { !store.config.ignoredProjects.contains($0.path) }.count
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tab = t }
                } label: {
                    HStack(spacing: 6) {
                        Text(t.rawValue.uppercased())
                            .font(Theme.mono(10, .bold))
                            .tracking(1.6)
                        Text("\(count)")
                            .font(Theme.mono(9, .semibold))
                            .foregroundStyle(tab == t ? Theme.void : Theme.tertiary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(tab == t ? Theme.cyan : Theme.hairline))
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(tab == t ? Theme.text : Theme.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if tab == t {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.cyan.opacity(0.08))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.cyan.opacity(0.35), lineWidth: 0.8))
                                .overlay(alignment: .bottom) {
                                    Capsule().fill(Theme.cyan).frame(width: 26, height: 2).glow(Theme.cyan, radius: 5).offset(y: 1)
                                }
                                .matchedGeometryEffect(id: "tab", in: tabNS)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .futureGlass(radius: 11)
    }
}

// MARK: - Header

struct HeaderBar: View {
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().strokeBorder(Theme.cyan.opacity(0.6), lineWidth: 1).frame(width: 18, height: 18)
                Circle().strokeBorder(Theme.cyan.opacity(0.25), lineWidth: 1).frame(width: 10, height: 10)
                Circle().fill(Theme.cyan).frame(width: 4, height: 4).glow(Theme.cyan, radius: 4)
            }
            Text("UPLINE")
                .font(.system(size: 13, weight: .heavy))
                .fontWidth(.expanded)
                .tracking(3)
                .foregroundStyle(LinearGradient(colors: [Theme.text, Theme.cyan.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
            NetworkPill(network: store.network)
            Spacer()
            IconButton(symbol: "arrow.triangle.2.circlepath", help: "Check everything now (⌘R)", spinning: store.isRefreshing) {
                store.refreshNow()
            }
            IconButton(symbol: "slider.horizontal.3", help: "Settings") {
                WindowManager.shared.showSettings()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

struct NetworkPill: View {
    let network: LocalNetwork
    var body: some View {
        let (label, color): (String, Color) = switch network {
        case .online: ("UPLINK", Theme.mint)
        case .checking: ("SYNCING", Theme.cyan)
        case .offline: ("OFFLINE", Theme.red)
        case .dnsBroken: ("DNS FAULT", Theme.amber)
        case .captivePortal: ("WIFI LOGIN", Theme.amber)
        }
        HStack(spacing: 5) {
            GlowDot(color: color, size: 5, pulsing: network != .online)
            Text(label).font(Theme.mono(8.5, .bold)).tracking(1.4).foregroundStyle(color)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.08)).overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.7)))
        .animation(.snappy, value: network)
    }
}

// MARK: - Hero

struct HeroPanel: View {
    @Environment(Store.self) private var store

    var body: some View {
        let watched = store.watched
        let problems = watched.filter { $0.state.health.isProblem }
        let overall = store.overall
        let accent = overall.isProblem ? overall.color : Theme.cyan

        HStack(spacing: 14) {
            RadarView(services: watched, size: 128, scanning: store.isRefreshing || store.isScanning, accent: accent)
            VStack(alignment: .leading, spacing: 8) {
                HUDLabel(store.network == .online ? "Signal" : "Local link", color: accent.opacity(0.8))
                Text(headline(problems: problems, total: watched.count))
                    .font(.system(size: 17, weight: .bold))
                    .fontWidth(.expanded)
                    .foregroundStyle(LinearGradient(colors: [Theme.text, accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
                Text(subline(problems: problems))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                HStack(spacing: 14) {
                    Stat(value: "\(watched.count)", label: "Watching")
                    Stat(value: "\(watched.filter { $0.tier == .active }.count)", label: "Hot")
                    Stat(value: "\(problems.count)", label: "Alerts", color: problems.isEmpty ? Theme.text : Theme.red)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassCard(radius: 18, tint: accent, lit: overall.isProblem)
        .overlay(alignment: .top) { ScanBeam(active: store.isRefreshing).padding(.horizontal, 18) }
        .animation(.snappy, value: problems.count)
    }

    private func headline(problems: [WatchedService], total: Int) -> String {
        if store.network.problem != nil { return "IT'S YOU,\nNOT THEM" }
        if total == 0 { return store.isScanning ? "SCANNING" : "NO SIGNALS YET" }
        if problems.isEmpty { return "ALL SYSTEMS\nNOMINAL" }
        if problems.count == 1 { return "\(problems[0].entry.name.uppercased())\n\(problems[0].state.health.shortLabel)" }
        return "\(problems.count) SERVICES\nIN TROUBLE"
    }

    private func subline(problems: [WatchedService]) -> String {
        if store.network.problem != nil { return "Your connection is the problem. Fix that first." }
        if let first = problems.first {
            let names = first.projects.prefix(2).map(\.name).joined(separator: ", ")
            return names.isEmpty ? first.reason : "\(first.reason). Hits \(names)."
        }
        if let last = store.lastRefresh { return "Every dependency answered. Checked \(last.shortAgo)." }
        return "Listening to status pages and live probes."
    }
}

struct Stat: View {
    let value: String
    let label: String
    var color: Color = Theme.text
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(Theme.mono(15, .bold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label.uppercased()).font(Theme.mono(8, .semibold)).tracking(1.2).foregroundStyle(Theme.tertiary)
        }
    }
}

struct ItsYouBanner: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .glow(Theme.amber, radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("It's you, not them").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                Text(text).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .glassCard(radius: 12, tint: Theme.amber, lit: true)
    }
}

// MARK: - Footer

struct FooterBar: View {
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 5)) { _ in
                Text(store.lastRefresh.map { "SYNCED \($0.shortAgo.uppercased())" } ?? "AWAITING FIRST SYNC")
                    .font(Theme.mono(8.5, .semibold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer()
            Text("\(store.projects.count) REPOS")
                .font(Theme.mono(8.5, .semibold)).tracking(1.3).foregroundStyle(Theme.tertiary)
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help("Quit Upline")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Theme.void.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

// MARK: - First run inside the panel

struct WelcomeCard: View {
    var body: some View {
        VStack(spacing: 18) {
            RadarView(services: [], size: 150, scanning: true)
            Text("KNOW BEFORE\nYOU DEBUG")
                .font(.system(size: 20, weight: .heavy)).fontWidth(.expanded)
                .multilineTextAlignment(.center)
                .foregroundStyle(LinearGradient(colors: [Theme.text, Theme.cyan], startPoint: .top, endPoint: .bottom))
            Text("Upline scans your projects, finds every service they depend on, and tells you the moment one of them goes down.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            NeonButton(title: "Set up Upline", symbol: "dot.radiowaves.left.and.right") {
                WindowManager.shared.showOnboarding()
            }
        }
    }
}

/// Hidden buttons that give the panel keyboard shortcuts.
struct KeyboardShortcuts: View {
    let refresh: () -> Void
    let back: () -> Void
    var body: some View {
        ZStack {
            Button("", action: refresh).keyboardShortcut("r", modifiers: .command)
            Button("", action: back).keyboardShortcut(.escape, modifiers: [])
            Button("", action: back).keyboardShortcut("[", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}
