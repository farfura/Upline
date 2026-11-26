import Foundation

// MARK: - Health

/// The combined state of a service, ordered by severity.
enum Health: Int, Codable, Comparable, CaseIterable {
    case operational = 0
    case unknown = 1
    case maintenance = 2
    case suspected = 3
    case degraded = 4
    case partialOutage = 5
    case majorOutage = 6

    static func < (a: Health, b: Health) -> Bool { a.rawValue < b.rawValue }

    var isProblem: Bool { self >= .suspected }

    var label: String {
        switch self {
        case .operational: "Operational"
        case .unknown: "Unknown"
        case .maintenance: "Maintenance"
        case .suspected: "Suspected"
        case .degraded: "Degraded"
        case .partialOutage: "Partial outage"
        case .majorOutage: "Major outage"
        }
    }

    var shortLabel: String {
        switch self {
        case .operational: "NOMINAL"
        case .unknown: "NO SIGNAL"
        case .maintenance: "MAINT"
        case .suspected: "SUSPECT"
        case .degraded: "DEGRADED"
        case .partialOutage: "PARTIAL"
        case .majorOutage: "DOWN"
        }
    }

    /// Maps Atlassian Statuspage style strings.
    static func fromStatuspage(_ s: String?) -> Health {
        switch (s ?? "").lowercased() {
        case "none", "operational", "up", "resolved", "completed", "postmortem": .operational
        case "minor", "degraded_performance", "degraded", "hasissues": .degraded
        case "major", "partial_outage", "partial": .partialOutage
        case "critical", "major_outage", "down", "outage": .majorOutage
        case "maintenance", "under_maintenance", "undermaintenance", "in_progress", "scheduled", "verifying": .maintenance
        default: .unknown
        }
    }
}

// MARK: - Catalog

enum ServiceCategory: String, Codable, CaseIterable {
    case ai, database, hosting, payments, auth, email, devtools, infra, web3, analytics, messaging, search, storage, other

    var title: String {
        switch self {
        case .ai: "AI"
        case .database: "Database"
        case .hosting: "Hosting"
        case .payments: "Payments"
        case .auth: "Auth"
        case .email: "Email"
        case .devtools: "Dev tools"
        case .infra: "Infrastructure"
        case .web3: "Web3"
        case .analytics: "Analytics"
        case .messaging: "Messaging"
        case .search: "Search"
        case .storage: "Storage"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .ai: "sparkles"
        case .database: "cylinder.split.1x2"
        case .hosting: "server.rack"
        case .payments: "creditcard"
        case .auth: "person.badge.key"
        case .email: "envelope"
        case .devtools: "hammer"
        case .infra: "network"
        case .web3: "link"
        case .analytics: "chart.xyaxis.line"
        case .messaging: "bubble.left.and.bubble.right"
        case .search: "magnifyingglass"
        case .storage: "externaldrive"
        case .other: "globe"
        }
    }
}

/// A cheap authenticated request that tells us whether *your* key works.
struct AuthCheck: Codable, Hashable {
    var url: String
    var envKeys: [String]
    var header: String = "Authorization"
    var valuePrefix: String = "Bearer "
    var extraHeaders: [String: String]? = nil
}

struct CatalogEntry: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var category: ServiceCategory
    /// Base URL of the public status page, if any.
    var statusPage: String?
    /// Probe targets: "https://host/path" or "tcp://host:port".
    var probes: [String]
    /// Package names. A trailing "*" means prefix match.
    var packages: [String] = []
    /// Environment variable prefixes or names.
    var envKeys: [String] = []
    /// Host suffixes that identify this service in URLs.
    var hosts: [String] = []
    /// Docker image names.
    var images: [String] = []
    var auth: AuthCheck? = nil
    /// Brand tint as hex.
    var color: String = "#7AA2FF"
    var isCustom: Bool = false
    /// Overrides how the status page is read: "statusio:<page id>", a feed URL, or "none" (link only).
    var statusFeed: String? = nil

    var monogram: String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)).uppercased() }
        return String(name.prefix(2)).capitalized
    }

    /// A service invented for a host we found but don't know.
    static func custom(host: String) -> CatalogEntry {
        let parts = host.split(separator: ".")
        let core = parts.count >= 2 ? parts[parts.count - 2] : Substring(host)
        let name = core.prefix(1).uppercased() + core.dropFirst()
        return CatalogEntry(
            id: "host:\(host)", name: String(name), category: .other, statusPage: nil,
            probes: ["https://\(host)"], hosts: [host], color: "#9AA4B8", isCustom: true
        )
    }
}

// MARK: - Projects

struct Detection: Codable, Hashable {
    var serviceID: String
    var evidence: [String]
    var regions: [String]
    var hosts: [String]
}

struct Project: Codable, Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var detections: [Detection]
    var lastActivity: Date?
    var stack: [String] = []
}

enum ActivityTier: Int, Comparable {
    case stale = 0, idle = 1, active = 2
    static func < (a: ActivityTier, b: ActivityTier) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .active: "ACTIVE"
        case .idle: "IDLE"
        case .stale: "DORMANT"
        }
    }
}

// MARK: - Live state

struct Component: Identifiable, Hashable {
    var id: String
    var name: String
    var health: Health
    var groupName: String?
}

struct IncidentUpdate: Hashable {
    var status: String
    var body: String
    var date: Date
}

struct Incident: Identifiable, Hashable {
    var id: String
    var name: String
    var status: String
    var impact: Health
    var createdAt: Date
    var updatedAt: Date
    var link: URL?
    var componentIDs: [String]
    var updates: [IncidentUpdate]
    var isMaintenance = false
}

enum StatusSource: String { case statuspage, instatus, statusio, feed }

struct OfficialStatus {
    var indicator: Health
    var description: String
    var components: [Component]
    var incidents: [Incident]
    var pageURL: URL
    var fetchedAt: Date
    var source: StatusSource
}

struct ProbeSample: Hashable {
    var date: Date
    var latencyMs: Double?
    var ok: Bool
    var detail: String?
}

enum AuthState: Equatable {
    case ok
    case invalidKey
    case rateLimited
    case noCredits
    case noKey
    case failed(String)

    var label: String {
        switch self {
        case .ok: "Key valid"
        case .invalidKey: "Key rejected"
        case .rateLimited: "Rate limited"
        case .noCredits: "Out of credits"
        case .noKey: "No key found in .env"
        case .failed(let s): s
        }
    }

    var isProblem: Bool {
        switch self {
        case .ok, .noKey: false
        default: true
        }
    }
}

struct ServiceState {
    var official: OfficialStatus?
    var officialError: String?
    var samples: [ProbeSample] = []
    var consecutiveFailures = 0
    var auth: AuthState?
    var health: Health = .unknown
    /// When the current problem started (as far as we saw it).
    var since: Date?
    var lastChecked: Date?

    var lastLatency: Double? { samples.last(where: { $0.ok })?.latencyMs }

    var uptimeRatio: Double? {
        guard !samples.isEmpty else { return nil }
        return Double(samples.filter(\.ok).count) / Double(samples.count)
    }
}

// MARK: - Config

struct CustomEndpoint: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var url: String
}

struct Config: Codable {
    var roots: [String] = []
    var mutedServices: Set<String> = []
    var projectMuted: [String: Set<String>] = [:]
    var projectAdded: [String: Set<String>] = [:]
    var pinnedProjects: Set<String> = []
    var ignoredProjects: Set<String> = []
    var componentSelections: [String: Set<String>] = [:]
    var deepChecks: Set<String> = []
    var customEndpoints: [CustomEndpoint] = []
    var pollSeconds: Double = 120
    var activeHours: Double = 3
    var staleDays: Double = 30
    var notifyResolved = true
    var notifyIdleProjects = false
    var onboarded = false

    init() {}

    // Tolerant decoding so new settings never wipe an older config file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        roots = (try? c.decodeIfPresent([String].self, forKey: .roots)) ?? d.roots
        mutedServices = (try? c.decodeIfPresent(Set<String>.self, forKey: .mutedServices)) ?? d.mutedServices
        projectMuted = (try? c.decodeIfPresent([String: Set<String>].self, forKey: .projectMuted)) ?? d.projectMuted
        projectAdded = (try? c.decodeIfPresent([String: Set<String>].self, forKey: .projectAdded)) ?? d.projectAdded
        pinnedProjects = (try? c.decodeIfPresent(Set<String>.self, forKey: .pinnedProjects)) ?? d.pinnedProjects
        ignoredProjects = (try? c.decodeIfPresent(Set<String>.self, forKey: .ignoredProjects)) ?? d.ignoredProjects
        componentSelections = (try? c.decodeIfPresent([String: Set<String>].self, forKey: .componentSelections)) ?? d.componentSelections
        deepChecks = (try? c.decodeIfPresent(Set<String>.self, forKey: .deepChecks)) ?? d.deepChecks
        customEndpoints = (try? c.decodeIfPresent([CustomEndpoint].self, forKey: .customEndpoints)) ?? d.customEndpoints
        pollSeconds = (try? c.decodeIfPresent(Double.self, forKey: .pollSeconds)) ?? d.pollSeconds
        activeHours = (try? c.decodeIfPresent(Double.self, forKey: .activeHours)) ?? d.activeHours
        staleDays = (try? c.decodeIfPresent(Double.self, forKey: .staleDays)) ?? d.staleDays
        notifyResolved = (try? c.decodeIfPresent(Bool.self, forKey: .notifyResolved)) ?? d.notifyResolved
        notifyIdleProjects = (try? c.decodeIfPresent(Bool.self, forKey: .notifyIdleProjects)) ?? d.notifyIdleProjects
        onboarded = (try? c.decodeIfPresent(Bool.self, forKey: .onboarded)) ?? d.onboarded
    }

    static let candidateRoots = [
        "~/Projects", "~/projects", "~/Developer", "~/code", "~/Code", "~/dev", "~/Dev",
        "~/work", "~/Work", "~/src", "~/GitHub", "~/github", "~/repos", "~/Repos", "~/Sites", "~/workspace",
    ]

    static func defaultRoots() -> [String] {
        let fm = FileManager.default
        var seen = Set<String>()
        return candidateRoots.filter { root in
            let path = (root as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return false }
            // Case insensitive file systems list the same folder twice.
            let real = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? path
            return seen.insert(real.lowercased()).inserted
        }
    }
}

extension String {
    var expandingTilde: String { (self as NSString).expandingTildeInPath }
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
}
