import AppKit
import Foundation
import Observation

struct WatchedService: Identifiable {
    var id: String { entry.id }
    let entry: CatalogEntry
    let state: ServiceState
    let projects: [Project]
    let tier: ActivityTier
    let regions: [String]
    let reason: String
}

@MainActor
@Observable
final class Store {
    static let shared = Store()

    private(set) var config: Config
    private(set) var catalog: [String: CatalogEntry]
    private(set) var projects: [Project]
    private(set) var states: [String: ServiceState] = [:]
    private(set) var reasons: [String: String] = [:]
    private(set) var network: LocalNetwork = .checking
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false
    private(set) var isScanning = false
    private(set) var scan = ScanProgress()
    private(set) var liveActivity: [String: Date] = [:]
    /// Bumps every time something visible changes, for cheap animations.
    private(set) var pulse = 0

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var activity: ActivityMonitor?
    @ObservationIgnored private var wake: WakeObserver?
    @ObservationIgnored private var lastStatusFetch: [String: Date] = [:]
    @ObservationIgnored private var lastProbe: [String: Date] = [:]
    @ObservationIgnored private var lastAuth: [String: Date] = [:]
    @ObservationIgnored private var notified: Set<String> = []
    @ObservationIgnored private var suppressTransitionAlerts = false
    @ObservationIgnored private var wakeTask: Task<Void, Never>?

    private init() {
        var config = Persistence.loadConfig()
        if config.roots.isEmpty { config.roots = Config.defaultRoots() }
        self.config = config
        let entries = Catalog.load()
        self.catalog = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        self.projects = Persistence.loadProjects()
    }

    // MARK: Lifecycle

    func start() {
        Notifier.requestPermission()
        activity = ActivityMonitor { [weak self] paths in self?.noteActivity(paths) }
        activity?.start(paths: config.roots)
        wake = WakeObserver(
            onWake: { [weak self] in self?.scheduleWakeCheck(delay: 2) },
            onNetwork: { [weak self] up in
                guard let self else { return }
                if up { self.scheduleWakeCheck(delay: 1) } else { self.network = .offline; self.pulse += 1 }
            }
        )
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await self?.tick(force: false)
            }
        }
        if config.onboarded { scheduleWakeCheck(delay: 0) }
    }

    func mutate(_ change: (inout Config) -> Void) {
        let oldRoots = config.roots
        change(&config)
        Persistence.save(config)
        if oldRoots != config.roots { activity?.start(paths: config.roots) }
        recomputeAll()
    }

    // MARK: Derived data

    /// Which projects use each watched service, after mutes.
    var usage: [String: [Project]] {
        var map: [String: [Project]] = [:]
        for p in projects where !config.ignoredProjects.contains(p.path) {
            var ids = Set(p.detections.map(\.serviceID)).union(config.projectAdded[p.path] ?? [])
            ids.subtract(config.projectMuted[p.path] ?? [])
            for id in ids where !config.mutedServices.contains(id) { map[id, default: []].append(p) }
        }
        for c in config.customEndpoints where map[customID(c)] == nil { map[customID(c)] = [] }
        return map
    }

    func customID(_ c: CustomEndpoint) -> String { "custom:\(c.id.uuidString)" }

    func entry(for id: String) -> CatalogEntry? {
        if let e = catalog[id] { return e }
        if id.hasPrefix("host:") { return .custom(host: String(id.dropFirst(5))) }
        if id.hasPrefix("custom:"), let c = config.customEndpoints.first(where: { customID($0) == id }) {
            let host = URL(string: c.url)?.host ?? c.url
            return CatalogEntry(id: id, name: c.name.isEmpty ? host : c.name, category: .other, statusPage: nil,
                                probes: [c.url], hosts: [host], color: "#4DF3FF", isCustom: true)
        }
        return nil
    }

    func tier(of project: Project) -> ActivityTier {
        if config.pinnedProjects.contains(project.path) { return .active }
        let last = [project.lastActivity, liveActivity[project.path]].compactMap { $0 }.max() ?? .distantPast
        let age = Date().timeIntervalSince(last)
        if age < config.activeHours * 3600 { return .active }
        if age < config.staleDays * 86400 { return .idle }
        return .stale
    }

    func regions(for id: String, in projects: [Project]) -> [String] {
        Array(Set(projects.flatMap { p in p.detections.filter { $0.serviceID == id }.flatMap(\.regions) })).sorted()
    }

    func probeTargets(for entry: CatalogEntry, in projects: [Project]) -> [String] {
        var out: [String] = []
        let fromProjects = projects.flatMap { p in p.detections.filter { $0.serviceID == entry.id }.flatMap(\.hosts) }
        for t in fromProjects + entry.probes where !out.contains(t) { out.append(t) }
        return Array(out.prefix(3))
    }

    var watched: [WatchedService] {
        let use = usage
        return use.compactMap { id, projects -> WatchedService? in
            guard let entry = entry(for: id) else { return nil }
            let tier: ActivityTier = id.hasPrefix("custom:") ? .active : (projects.map { self.tier(of: $0) }.max() ?? .stale)
            return WatchedService(
                entry: entry, state: states[id] ?? ServiceState(), projects: projects.sorted { $0.name < $1.name },
                tier: tier, regions: regions(for: id, in: projects), reason: reasons[id] ?? "Waiting for first check"
            )
        }
        .sorted { a, b in
            if a.state.health.isProblem != b.state.health.isProblem { return a.state.health.isProblem }
            if a.state.health != b.state.health { return a.state.health > b.state.health }
            if a.tier != b.tier { return a.tier > b.tier }
            return a.entry.name.lowercased() < b.entry.name.lowercased()
        }
    }

    var overall: Health {
        if network.problem != nil { return .unknown }
        return watched.filter { $0.tier != .stale }.map(\.state.health).max() ?? .operational
    }

    var problemServices: [WatchedService] { watched.filter { $0.state.health.isProblem } }

    // MARK: Activity

    private func noteActivity(_ paths: [String]) {
        let now = Date()
        var changed = false
        for p in projects {
            let prefix = p.path + "/"
            if paths.contains(where: { $0.hasPrefix(prefix) || $0 == p.path }) {
                if let last = liveActivity[p.path], now.timeIntervalSince(last) < 60 { continue }
                liveActivity[p.path] = now
                changed = true
            }
        }
        if changed { pulse += 1 }
    }

    // MARK: Scanning

    func rescan() async {
        guard !isScanning else { return }
        isScanning = true
        scan = ScanProgress()
        let scanner = ProjectScanner(catalog: Array(catalog.values))
        let roots = config.roots
        let repos = await Task.detached(priority: .userInitiated) { scanner.findRepos(roots: roots, ignored: []) }.value
        scan.reposFound = repos.count

        var results: [Project] = []
        var found = Set<String>()
        for repo in repos {
            scan.currentPath = repo.path.abbreviatingHome
            let project = await Task.detached(priority: .userInitiated) { scanner.scan(repo: repo) }.value
            results.append(project)
            scan.reposScanned += 1
            for d in project.detections where found.insert(d.serviceID).inserted {
                if let name = entry(for: d.serviceID)?.name {
                    scan.lastHits.insert(name, at: 0)
                    if scan.lastHits.count > 6 { scan.lastHits.removeLast() }
                }
            }
            scan.servicesFound = found.count
        }
        projects = results
        Persistence.save(results)
        isScanning = false
        pulse += 1
        await tick(force: true)
    }

    // MARK: Checking

    private enum Outcome: Sendable {
        case status(String, OfficialStatus?, String?)
        case probe(String, ProbeSample)
        case auth(String, AuthState)
    }

    func refreshNow() {
        Task { await tick(force: true) }
    }

    func scheduleWakeCheck(delay: Double) {
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.wakeCheck()
        }
    }

    /// The "you just opened your laptop" check: wait for the network, check everything, then send
    /// one summary instead of a pile of separate alerts.
    func wakeCheck() async {
        network = .checking
        var net = LocalNetwork.offline
        for attempt in 0..<6 {
            net = await Connectivity.diagnose()
            if net == .online || Task.isCancelled { break }
            try? await Task.sleep(for: .seconds(attempt < 2 ? 3 : 6))
        }
        network = net
        pulse += 1
        guard net == .online else {
            if let problem = net.problem { Notifier.send(id: "upline.local", title: "It's you, not them", body: problem, sound: false) }
            return
        }
        while isRefreshing { try? await Task.sleep(for: .milliseconds(250)) }
        suppressTransitionAlerts = true
        await tick(force: true)
        suppressTransitionAlerts = false

        let problems = watched.filter { $0.state.health.isProblem && shouldAlert($0) }
        guard !problems.isEmpty else { return }
        for p in problems { notified.insert(p.id) }
        let title = problems.count == 1
            ? "\(problems[0].entry.name): \(problems[0].state.health.label.lowercased())"
            : "\(problems.count) services have problems"
        let body = problems.prefix(4).map { s in
            var line = "\(s.entry.name) \(s.state.health.label.lowercased())"
            if let since = s.state.since { line += " since \(since.formatted(date: .omitted, time: .shortened))" }
            let names = s.projects.filter { tier(of: $0) != .stale }.prefix(3).map(\.name)
            if !names.isEmpty { line += ". Affects \(names.joined(separator: ", "))" }
            return line
        }.joined(separator: "\n")
        Notifier.send(id: "upline.wake.\(Date().timeIntervalSince1970)", title: title, body: body,
                      url: problems.count == 1 ? problems[0].entry.statusPage.flatMap(URL.init(string:)) : nil)
    }

    func tick(force: Bool) async {
        guard !isRefreshing, config.onboarded || force else { return }
        if network == .offline && !force { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let poll = config.pollSeconds * (lowPower ? 2 : 1)
        let use = usage

        var statusJobs: [(String, String, String?)] = []
        var probeJobs: [(String, String)] = []
        var authJobs: [(String, AuthCheck, [Project])] = []

        for (id, projects) in use {
            guard let entry = entry(for: id) else { continue }
            let tier: ActivityTier = id.hasPrefix("custom:") ? .active : (projects.map { self.tier(of: $0) }.max() ?? .stale)
            if let page = entry.statusPage, entry.statusFeed != "none",
               force || now.timeIntervalSince(lastStatusFetch[id] ?? .distantPast) >= poll {
                statusJobs.append((id, page, entry.statusFeed))
                lastStatusFetch[id] = now
            }
            let probeEvery: Double = switch tier {
            case .active: min(60, poll)
            case .idle: poll
            case .stale: poll * 3
            }
            if force || now.timeIntervalSince(lastProbe[id] ?? .distantPast) >= probeEvery {
                for target in probeTargets(for: entry, in: projects) { probeJobs.append((id, target)) }
                lastProbe[id] = now
            }
            if config.deepChecks.contains(id), let spec = entry.auth,
               force || now.timeIntervalSince(lastAuth[id] ?? .distantPast) >= 600 {
                authJobs.append((id, spec, projects))
                lastAuth[id] = now
            }
        }
        guard !statusJobs.isEmpty || !probeJobs.isEmpty || !authJobs.isEmpty else { return }

        let outcomes: [Outcome] = await withTaskGroup(of: Outcome.self) { group in
            var running = 0
            var results: [Outcome] = []
            var queue: [@Sendable () async -> Outcome] = []
            for (id, page, feed) in statusJobs {
                queue.append {
                    do { return .status(id, try await StatusClient.shared.fetch(base: page, feed: feed), nil) }
                    catch { return .status(id, nil, "No readable status feed") }
                }
            }
            for (id, target) in probeJobs { queue.append { .probe(id, await Prober.probe(target)) } }
            for (id, spec, projects) in authJobs { queue.append { .auth(id, await AuthChecker.check(spec, projects: projects)) } }

            for job in queue {
                if running >= 10, let r = await group.next() { results.append(r); running -= 1 }
                group.addTask(operation: job)
                running += 1
            }
            for await r in group { results.append(r) }
            return results
        }

        // Is it me? If most probes failed at once, check our own connection before blaming anyone.
        let probes = outcomes.compactMap { o -> ProbeSample? in if case .probe(_, let s) = o { return s }; return nil }
        if probes.count >= 3, Double(probes.filter { !$0.ok }.count) / Double(probes.count) >= 0.6 {
            let net = await Connectivity.diagnose()
            network = net
            if net != .online { pulse += 1; return }
        } else if network != .online, probes.contains(where: \.ok) {
            network = .online
        }

        // Merge probe samples per service (a service with several targets fails only if all fail).
        var probeByService: [String: [ProbeSample]] = [:]
        for o in outcomes {
            switch o {
            case .status(let id, let status, let error):
                var s = states[id] ?? ServiceState()
                if let status { s.official = status; s.officialError = nil } else { s.officialError = error }
                states[id] = s
            case .probe(let id, let sample):
                probeByService[id, default: []].append(sample)
            case .auth(let id, let auth):
                var s = states[id] ?? ServiceState()
                s.auth = auth
                states[id] = s
            }
        }
        for (id, samples) in probeByService {
            var s = states[id] ?? ServiceState()
            let anyOK = samples.contains(where: \.ok)
            let best = samples.filter(\.ok).min { ($0.latencyMs ?? .infinity) < ($1.latencyMs ?? .infinity) }
            let merged = best ?? samples.first ?? ProbeSample(date: now, latencyMs: nil, ok: false)
            s.samples.append(merged)
            if s.samples.count > 120 { s.samples.removeFirst(s.samples.count - 120) }
            s.consecutiveFailures = anyOK ? 0 : s.consecutiveFailures + 1
            states[id] = s
        }

        let touched = Set(outcomes.map { o -> String in
            switch o { case .status(let id, _, _), .probe(let id, _), .auth(let id, _): return id }
        })
        for id in touched { recompute(id) }
        lastRefresh = Date()
        pulse += 1
    }

    // MARK: Health

    func recomputeAll() {
        for id in states.keys { recompute(id) }
        pulse += 1
    }

    private func recompute(_ id: String) {
        guard var s = states[id], let entry = entry(for: id) else { return }
        let projects = usage[id] ?? []
        let (health, reason) = Self.computeHealth(
            state: s, entry: entry,
            selection: config.componentSelections[id] ?? [],
            regions: regions(for: id, in: projects)
        )
        let old = s.health
        s.health = health
        s.lastChecked = Date()
        if health.isProblem && !old.isProblem { s.since = Date() }
        if !health.isProblem { s.since = nil }
        states[id] = s
        reasons[id] = reason
        handleTransition(id: id, entry: entry, from: old, to: health, reason: reason, projects: projects)
    }

    static func relevantComponents(_ comps: [Component], selection: Set<String>, regions: [String]) -> [Component] {
        if !selection.isEmpty { return comps.filter { selection.contains($0.id) } }
        guard !regions.isEmpty else { return comps }
        return comps.filter { c in
            let text = (c.name + " " + (c.groupName ?? "")).lowercased()
            let mentioned = ProjectScanner.regions(in: text.replacingOccurrences(of: " ", with: "-"))
            if mentioned.isEmpty { return true }
            return regions.contains { text.contains($0) }
        }
    }

    static func computeHealth(state s: ServiceState, entry: CatalogEntry, selection: Set<String>, regions: [String]) -> (Health, String) {
        var health = Health.unknown
        var reason = "Waiting for first check"

        if let o = s.official {
            let rel = relevantComponents(o.components, selection: selection, regions: regions)
            let relIDs = Set(rel.map(\.id))
            var h = o.components.isEmpty ? o.indicator : (rel.map(\.health).filter { $0 != .unknown }.max() ?? .operational)
            var worstIncident: Incident?
            for inc in o.incidents {
                let affects = inc.componentIDs.isEmpty
                    ? (o.components.isEmpty || (selection.isEmpty && regions.isEmpty))
                    : !relIDs.isDisjoint(with: inc.componentIDs)
                if affects, inc.impact >= h {
                    h = max(h, inc.impact)
                    worstIncident = inc
                }
            }
            health = h
            if let inc = worstIncident {
                reason = inc.name
            } else if let bad = rel.filter({ $0.health.isProblem }).max(by: { $0.health < $1.health }) {
                reason = "\(bad.name): \(bad.health.label.lowercased())"
            } else if h == .operational {
                reason = regions.isEmpty ? "Status page clear" : "Status page clear in \(regions.joined(separator: ", "))"
            } else {
                reason = o.description
            }
        }

        let probeFails = s.consecutiveFailures
        let lastDetail = s.samples.last?.detail ?? ""
        if probeFails >= 2 {
            if s.official == nil {
                if probeFails >= 3 { health = max(health, .majorOutage); reason = "Not responding: \(lastDetail)" }
                else { health = max(health, .suspected); reason = "Probe failing: \(lastDetail)" }
            } else if !health.isProblem {
                health = .suspected
                reason = "API not answering (\(lastDetail)) but the status page still says fine"
            }
        } else if s.official == nil, let last = s.samples.last, last.ok {
            health = .operational
            reason = entry.statusPage == nil ? "Probe healthy, no public status feed" : "Probe healthy"
        } else if s.official == nil, s.samples.count == 1, s.samples.last?.ok == false {
            reason = "First probe failed, rechecking"
        }

        if let auth = s.auth, auth.isProblem {
            health = max(health, .degraded)
            reason = "Your key: \(auth.label.lowercased())" + (health > .degraded ? ". " + reason : "")
        }
        return (health, reason)
    }

    // MARK: Alerts

    private func shouldAlert(_ s: WatchedService) -> Bool {
        if s.tier == .active { return true }
        if s.tier == .idle { return config.notifyIdleProjects }
        return false
    }

    private func handleTransition(id: String, entry: CatalogEntry, from old: Health, to new: Health, reason: String, projects: [Project]) {
        guard old != new, !suppressTransitionAlerts, old != .unknown || new.isProblem else { return }
        let tier: ActivityTier = id.hasPrefix("custom:") ? .active : (projects.map { self.tier(of: $0) }.max() ?? .stale)
        let alertable = tier == .active || (tier == .idle && config.notifyIdleProjects)
        let names = projects.filter { self.tier(of: $0) != .stale }.prefix(3).map(\.name)
        let affects = names.isEmpty ? "" : "\nAffects \(names.joined(separator: ", "))"
        let link = entry.statusPage.flatMap(URL.init(string:))

        if new.isProblem && (!old.isProblem || new > old) {
            guard alertable else { return }
            let escalated = old.isProblem
            notified.insert(id)
            let title = escalated && old == .suspected
                ? "\(entry.name): confirmed \(new.label.lowercased())"
                : "\(entry.name): \(new.label.lowercased())"
            Notifier.send(id: "upline.\(id).\(new.rawValue)", title: title, body: reason + affects, url: link)
        } else if !new.isProblem && old.isProblem {
            guard config.notifyResolved, notified.contains(id) else { return }
            notified.remove(id)
            Notifier.send(id: "upline.\(id).ok", title: "\(entry.name) is back", body: "Looks healthy again. Go ahead and retry.", sound: false)
        }
    }

    // MARK: Actions

    func togglePin(_ project: Project) {
        mutate { c in
            if c.pinnedProjects.contains(project.path) { c.pinnedProjects.remove(project.path) } else { c.pinnedProjects.insert(project.path) }
        }
    }

    func toggleIgnore(_ project: Project) {
        mutate { c in
            if c.ignoredProjects.contains(project.path) { c.ignoredProjects.remove(project.path) } else { c.ignoredProjects.insert(project.path) }
        }
    }

    func setMuted(_ serviceID: String, muted: Bool) {
        mutate { c in if muted { c.mutedServices.insert(serviceID) } else { c.mutedServices.remove(serviceID) } }
    }

    func setMuted(_ serviceID: String, in project: Project, muted: Bool) {
        mutate { c in
            var set = c.projectMuted[project.path] ?? []
            if muted { set.insert(serviceID) } else { set.remove(serviceID) }
            c.projectMuted[project.path] = set
        }
    }

    func setDeepCheck(_ serviceID: String, on: Bool) {
        mutate { c in if on { c.deepChecks.insert(serviceID) } else { c.deepChecks.remove(serviceID) } }
        if on { lastAuth[serviceID] = nil; refreshNow() } else {
            states[serviceID]?.auth = nil
            recompute(serviceID)
        }
    }

    func toggleComponent(_ serviceID: String, componentID: String, all: [Component]) {
        mutate { c in
            var set = c.componentSelections[serviceID] ?? []
            if set.isEmpty { set = Set(all.map(\.id)) }
            if set.contains(componentID) { set.remove(componentID) } else { set.insert(componentID) }
            c.componentSelections[serviceID] = set.count == all.count ? [] : set
        }
    }

    func addCustomEndpoint(name: String, url: String) {
        var u = url.trimmingCharacters(in: .whitespaces)
        if !u.contains("://") { u = "https://" + u }
        mutate { $0.customEndpoints.append(CustomEndpoint(name: name, url: u)) }
        refreshNow()
    }

    func removeCustomEndpoint(_ c: CustomEndpoint) {
        mutate { $0.customEndpoints.removeAll { $0.id == c.id } }
        states[customID(c)] = nil
    }

    func completeOnboarding() {
        mutate { $0.onboarded = true }
        scheduleWakeCheck(delay: 0)
    }
}
