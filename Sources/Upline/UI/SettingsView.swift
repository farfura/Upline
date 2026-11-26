import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general = "General"
        case folders = "Folders"
        case endpoints = "Endpoints"
        case muted = "Muted"
        case about = "About"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: "gauge.with.dots.needle.67percent"
            case .folders: "folder"
            case .endpoints: "point.3.connected.trianglepath.dotted"
            case .muted: "bell.slash"
            case .about: "dot.radiowaves.left.and.right"
            }
        }
    }

    @Environment(Store.self) private var store
    @State private var pane: Pane = .general
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.hairline).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(pane.rawValue.uppercased())
                        .font(.system(size: 18, weight: .heavy)).fontWidth(.expanded).tracking(1.5)
                        .foregroundStyle(LinearGradient(colors: [Theme.text, Theme.cyan], startPoint: .leading, endPoint: .trailing))
                    switch pane {
                    case .general: GeneralPane()
                    case .folders: FoldersPane()
                    case .endpoints: EndpointsPane()
                    case .muted: MutedPane()
                    case .about: AboutPane()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 680, height: 480)
        .background(SpaceBackground(intensity: 0.7))
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(Theme.cyan).frame(width: 6, height: 6).glow(Theme.cyan, radius: 5)
                Text("UPLINE").font(.system(size: 12, weight: .heavy)).fontWidth(.expanded).tracking(2.5).foregroundStyle(Theme.text)
            }
            .padding(.bottom, 18)
            .padding(.top, 30)
            ForEach(Pane.allCases) { p in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { pane = p }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: p.symbol).font(.system(size: 12)).frame(width: 16)
                        Text(p.rawValue).font(.system(size: 12.5, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(pane == p ? Theme.text : Theme.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background {
                        if pane == p {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.cyan.opacity(0.1))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.cyan.opacity(0.3), lineWidth: 0.8))
                                .overlay(alignment: .leading) { Capsule().fill(Theme.cyan).frame(width: 2.5, height: 14).glow(Theme.cyan, radius: 4).offset(x: -1) }
                                .matchedGeometryEffect(id: "pane", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(width: 180)
        .background(Theme.void.opacity(0.5))
    }
}

// MARK: - Panes

struct SettingRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(12)
        .glassCard(radius: 12)
    }
}

struct GeneralPane: View {
    @Environment(Store.self) private var store
    @State private var loginTick = false

    var body: some View {
        let c = store.config
        VStack(spacing: 8) {
            SettingRow(title: "Check every \(Int(c.pollSeconds / 60)) min", subtitle: "Status pages and idle projects. Services used by projects you're working on are probed every minute.") {
                Slider(value: Binding(get: { c.pollSeconds / 60 }, set: { v in store.mutate { $0.pollSeconds = (v.rounded()) * 60 } }), in: 1...10, step: 1)
                    .frame(width: 140).tint(Theme.cyan)
            }
            SettingRow(title: "Hot for \(Int(c.activeHours)) h after you touch a project", subtitle: "Projects you've edited recently get full alerts. Detected from file activity, no extra permissions.") {
                Slider(value: Binding(get: { c.activeHours }, set: { v in store.mutate { $0.activeHours = v.rounded() } }), in: 1...24, step: 1)
                    .frame(width: 140).tint(Theme.cyan)
            }
            SettingRow(title: "Dormant after \(Int(c.staleDays)) days", subtitle: "Untouched projects go quiet unless you pin them.") {
                Slider(value: Binding(get: { c.staleDays }, set: { v in store.mutate { $0.staleDays = v.rounded() } }), in: 7...120, step: 1)
                    .frame(width: 140).tint(Theme.cyan)
            }
            SettingRow(title: "Alert for idle projects", subtitle: "Off means idle projects only show a quiet dot in the menu.") {
                Toggle("", isOn: Binding(get: { c.notifyIdleProjects }, set: { v in store.mutate { $0.notifyIdleProjects = v } }))
                    .toggleStyle(.switch).tint(Theme.cyan).labelsHidden()
            }
            SettingRow(title: "Tell me when it's back", subtitle: "A quiet notification when a service recovers, so you know when to retry.") {
                Toggle("", isOn: Binding(get: { c.notifyResolved }, set: { v in store.mutate { $0.notifyResolved = v } }))
                    .toggleStyle(.switch).tint(Theme.cyan).labelsHidden()
            }
            SettingRow(title: "Launch at login", subtitle: "Runs the wake check every time you open your laptop.") {
                Toggle("", isOn: Binding(
                    get: { _ = loginTick; return SMAppService.mainApp.status == .enabled },
                    set: { on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
                        loginTick.toggle()
                    }
                ))
                .toggleStyle(.switch).tint(Theme.cyan).labelsHidden()
            }
        }
    }
}

struct FoldersPane: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upline looks for git repositories up to four levels inside these folders.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            ForEach(store.config.roots, id: \.self) { root in
                HStack {
                    Image(systemName: "folder.fill").foregroundStyle(Theme.cyan)
                    Text(root.abbreviatingHome).font(Theme.mono(11.5)).foregroundStyle(Theme.text)
                    Spacer()
                    Button {
                        store.mutate { $0.roots.removeAll { $0 == root } }
                    } label: { Image(systemName: "minus.circle").foregroundStyle(Theme.red) }
                        .buttonStyle(.plain)
                }
                .padding(10)
                .glassCard(radius: 10)
            }
            HStack {
                NeonButton(title: "Add folder", symbol: "plus", prominent: false) {
                    if let p = pickFolder() { store.mutate { if !$0.roots.contains(p) { $0.roots.append(p) } } }
                }
                NeonButton(title: store.isScanning ? "Scanning \(store.scan.reposScanned)/\(store.scan.reposFound)" : "Rescan now", symbol: "dot.radiowaves.left.and.right") {
                    Task { await store.rescan() }
                }
                .disabled(store.isScanning)
            }
            let ignored = store.projects.filter { store.config.ignoredProjects.contains($0.path) }
            if !ignored.isEmpty {
                HUDLabel("Ignored projects").padding(.top, 10)
                ForEach(ignored) { p in
                    HStack {
                        Text(p.name).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        Text(p.path.abbreviatingHome).font(Theme.mono(9.5)).foregroundStyle(Theme.tertiary).lineLimit(1)
                        Spacer()
                        Button("Watch again") { store.toggleIgnore(p) }.buttonStyle(.plain).foregroundStyle(Theme.cyan).font(.system(size: 11, weight: .semibold))
                    }
                    .padding(8).glassCard(radius: 9)
                }
            }
        }
    }
}

struct EndpointsPane: View {
    @Environment(Store.self) private var store
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Watch anything with a URL: your own production API, a health route, a partner sandbox. Manual endpoints always alert.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("Name", text: $name).textFieldStyle(.plain).frame(width: 130)
                    .padding(8).glassCard(radius: 8)
                TextField("https://api.example.com/health", text: $url).textFieldStyle(.plain)
                    .padding(8).glassCard(radius: 8)
                NeonButton(title: "Add", symbol: "plus") {
                    guard !url.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    store.addCustomEndpoint(name: name, url: url)
                    name = ""; url = ""
                }
            }
            .font(Theme.mono(11))
            ForEach(store.config.customEndpoints) { c in
                let state = store.states[store.customID(c)]
                HStack(spacing: 10) {
                    GlowDot(color: (state?.health ?? .unknown).color, size: 6, pulsing: state?.health.isProblem == true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.name.isEmpty ? (URL(string: c.url)?.host ?? c.url) : c.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                        Text(c.url).font(Theme.mono(9.5)).foregroundStyle(Theme.tertiary).lineLimit(1)
                    }
                    Spacer()
                    Text(state?.lastLatency.map { "\(Int($0))ms" } ?? "...").font(Theme.mono(10)).foregroundStyle(Theme.secondary)
                    Button { store.removeCustomEndpoint(c) } label: { Image(systemName: "trash").foregroundStyle(Theme.red) }.buttonStyle(.plain)
                }
                .padding(10).glassCard(radius: 10)
            }
        }
    }
}

struct MutedPane: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let muted = store.config.mutedServices.sorted()
            if muted.isEmpty {
                Text("Nothing muted. Mute a service from its detail page or the setup screen.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            ForEach(muted, id: \.self) { id in
                if let e = store.entry(for: id) {
                    HStack(spacing: 10) {
                        Monogram(entry: e, size: 24).saturation(0)
                        Text(e.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Button("Unmute") { store.setMuted(id, muted: false) }
                            .buttonStyle(.plain).foregroundStyle(Theme.cyan).font(.system(size: 11, weight: .semibold))
                    }
                    .padding(9).glassCard(radius: 10)
                }
            }
            HUDLabel("Your catalog").padding(.top, 12)
            Text("Add or override services in \(Catalog.userFileURL.path.abbreviatingHome). Entries with the same id replace the built in ones.")
                .font(.system(size: 11)).foregroundStyle(Theme.tertiary).textSelection(.enabled)
            NeonButton(title: "Reveal catalog folder", symbol: "folder", prominent: false) {
                NSWorkspace.shared.activateFileViewerSelecting([Persistence.directory])
            }
        }
    }
}

struct AboutPane: View {
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            RadarView(services: [], size: 120)
            VStack(alignment: .leading, spacing: 10) {
                Text("Upline").font(.system(size: 22, weight: .heavy)).fontWidth(.expanded).foregroundStyle(Theme.text)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .font(Theme.mono(10)).foregroundStyle(Theme.tertiary)
                Text("Status pages are often 20 to 60 minutes late. Upline reads them, then double checks by talking to the real API hosts, so you find out before you start debugging your own code.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                Text("\(Catalog.builtIn.count) services in the built in catalog.")
                    .font(Theme.mono(10.5)).foregroundStyle(Theme.cyan)
            }
        }
    }
}
