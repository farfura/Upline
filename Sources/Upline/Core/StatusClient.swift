import Foundation

/// Reads public status pages. Tries Atlassian Statuspage style JSON first (used by most
/// providers, and offered as a compatible endpoint by several others), then Instatus,
/// then plain RSS or Atom incident feeds.
actor StatusClient {
    static let shared = StatusClient()

    private var adapterCache: [String: StatusSource] = [:]
    private var deadPages: [String: Date] = [:]

    let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        c.timeoutIntervalForResource = 20
        c.httpAdditionalHeaders = ["User-Agent": "Upline/1.0 (macOS status monitor)", "Accept": "application/json, application/rss+xml, application/atom+xml, */*"]
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    enum Failure: Error { case noFeed, http(Int), parse }

    func fetch(base: String, feed: String? = nil) async throws -> OfficialStatus {
        let base = base.hasSuffix("/") ? String(base.dropLast()) : base
        if let feed, feed.hasPrefix("statusio:") {
            if let s = try await statusio(id: String(feed.dropFirst("statusio:".count)), page: base) { return s }
            throw Failure.parse
        }
        if let feed, feed.hasPrefix("http") {
            if let s = try await feedAt(urls: [feed], page: base) { return s }
            throw Failure.parse
        }
        // Don't hammer a page that has no machine readable feed. Retry once an hour.
        if let dead = deadPages[base], Date().timeIntervalSince(dead) < 3600 { throw Failure.noFeed }

        let order: [StatusSource]
        if let known = adapterCache[base] {
            order = [known] + [.statuspage, .instatus, .feed].filter { $0 != known }
        } else {
            order = [.statuspage, .instatus, .feed]
        }

        for source in order {
            do {
                let result: OfficialStatus?
                switch source {
                case .statuspage: result = try await statuspage(base)
                case .instatus: result = try await instatus(base)
                case .feed: result = try await self.feed(base)
                case .statusio: result = nil
                }
                if let result {
                    adapterCache[base] = source
                    deadPages[base] = nil
                    return result
                }
            } catch let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .dnsLookupFailed].contains(e.code) {
                throw e // a network problem, not a missing feed
            } catch {
                continue
            }
        }
        deadPages[base] = Date()
        throw Failure.noFeed
    }

    // MARK: Adapters

    private func getJSON(_ url: String) async throws -> [String: Any]? {
        guard let u = URL(string: url) else { return nil }
        let (data, resp) = try await session.data(from: u)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func statuspage(_ base: String) async throws -> OfficialStatus? {
        guard let json = try await getJSON(base + "/api/v2/summary.json"),
              let status = json["status"] as? [String: Any] else { return nil }

        let pageURL = URL(string: ((json["page"] as? [String: Any])?["url"] as? String) ?? base) ?? URL(string: base)!
        let rawComponents = json["components"] as? [[String: Any]] ?? []
        var groupNames: [String: String] = [:]
        for c in rawComponents where (c["group"] as? Bool) == true {
            if let id = c["id"] as? String, let name = c["name"] as? String { groupNames[id] = name }
        }
        let components: [Component] = rawComponents.compactMap { c in
            guard (c["group"] as? Bool) != true, let id = c["id"] as? String, let name = c["name"] as? String else { return nil }
            return Component(id: id, name: name, health: Health.fromStatuspage(c["status"] as? String),
                             groupName: (c["group_id"] as? String).flatMap { groupNames[$0] })
        }

        var incidents = (json["incidents"] as? [[String: Any]] ?? []).compactMap { parseIncident($0, maintenance: false) }
        let maint = (json["scheduled_maintenances"] as? [[String: Any]] ?? []).compactMap { parseIncident($0, maintenance: true) }
        incidents += maint.filter { $0.status.lowercased() == "in_progress" || $0.status.lowercased() == "verifying" }

        return OfficialStatus(
            indicator: Health.fromStatuspage(status["indicator"] as? String),
            description: status["description"] as? String ?? "",
            components: components,
            incidents: incidents,
            pageURL: pageURL,
            fetchedAt: Date(),
            source: .statuspage
        )
    }

    private func parseIncident(_ i: [String: Any], maintenance: Bool) -> Incident? {
        guard let id = i["id"] as? String, let name = i["name"] as? String else { return nil }
        let updates: [IncidentUpdate] = (i["incident_updates"] as? [[String: Any]] ?? []).compactMap { u in
            guard let body = u["body"] as? String else { return nil }
            return IncidentUpdate(status: u["status"] as? String ?? "", body: body, date: DateParse.iso(u["created_at"] as? String) ?? Date())
        }
        let comps = (i["components"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        var impact = Health.fromStatuspage(i["impact"] as? String)
        if maintenance { impact = .maintenance }
        if impact == .operational || impact == .unknown { impact = .degraded }
        return Incident(
            id: id, name: name, status: i["status"] as? String ?? "",
            impact: impact,
            createdAt: DateParse.iso(i["created_at"] as? String) ?? Date(),
            updatedAt: DateParse.iso(i["updated_at"] as? String) ?? Date(),
            link: (i["shortlink"] as? String).flatMap(URL.init(string:)),
            componentIDs: comps, updates: updates, isMaintenance: maintenance
        )
    }

    private func instatus(_ base: String) async throws -> OfficialStatus? {
        guard let json = try await getJSON(base + "/summary.json"),
              let page = json["page"] as? [String: Any],
              let status = page["status"] as? String else { return nil }
        var incidents: [Incident] = []
        for (key, isMaint) in [("activeIncidents", false), ("activeMaintenances", true)] {
            for i in json[key] as? [[String: Any]] ?? [] {
                guard let id = i["id"] as? String, let name = i["name"] as? String else { continue }
                let started = DateParse.iso(i["started"] as? String) ?? Date()
                var impact = Health.fromStatuspage((i["impact"] as? String)?.lowercased().replacingOccurrences(of: "outage", with: "major_outage"))
                if isMaint { impact = .maintenance } else if impact == .unknown || impact == .operational { impact = .degraded }
                incidents.append(Incident(id: id, name: name, status: i["status"] as? String ?? "", impact: impact,
                                          createdAt: started, updatedAt: started,
                                          link: (i["url"] as? String).flatMap(URL.init(string:)),
                                          componentIDs: [], updates: [], isMaintenance: isMaint))
            }
        }
        let indicator = Health.fromStatuspage(status)
        return OfficialStatus(
            indicator: indicator,
            description: indicator == .operational ? "All systems operational" : indicator.label,
            components: [], incidents: incidents,
            pageURL: URL(string: page["url"] as? String ?? base) ?? URL(string: base)!,
            fetchedAt: Date(), source: .instatus
        )
    }

    /// Status.io pages (Neon, GitLab and others) have a public JSON API keyed by page id.
    private func statusio(id: String, page: String) async throws -> OfficialStatus? {
        guard let json = try await getJSON("https://api.status.io/1.0/status/\(id)"),
              let result = json["result"] as? [String: Any] else { return nil }
        func health(_ code: Any?) -> Health {
            switch (code as? Int) ?? 0 {
            case 100: .operational
            case 200: .maintenance
            case 300: .degraded
            case 400: .partialOutage
            case 500, 600: .majorOutage
            default: .unknown
            }
        }
        var components: [Component] = []
        for c in result["status"] as? [[String: Any]] ?? [] {
            let name = c["name"] as? String ?? "Component"
            let cid = c["id"] as? String ?? name
            let containers = c["containers"] as? [[String: Any]] ?? []
            if containers.isEmpty {
                components.append(Component(id: cid, name: name, health: health(c["status_code"]), groupName: nil))
            }
            for k in containers {
                let kname = k["name"] as? String ?? ""
                components.append(Component(id: cid + "/" + (k["id"] as? String ?? kname), name: name, health: health(k["status_code"]), groupName: kname))
            }
        }
        var incidents: [Incident] = []
        for i in result["incidents"] as? [[String: Any]] ?? [] {
            let messages = (i["messages"] as? [[String: Any]] ?? []).compactMap { m -> IncidentUpdate? in
                guard let body = m["details"] as? String else { return nil }
                return IncidentUpdate(status: "update", body: FeedParser.stripHTML(body), date: DateParse.iso(m["datetime"] as? String) ?? Date())
            }.sorted { $0.date > $1.date }
            let opened = DateParse.iso(i["datetime_open"] as? String) ?? Date()
            let affected = (i["components_affected"] as? [[String: Any]] ?? []).compactMap { $0["_id"] as? String ?? $0["id"] as? String }
            incidents.append(Incident(id: i["_id"] as? String ?? UUID().uuidString, name: i["name"] as? String ?? "Incident",
                                      status: "investigating", impact: .degraded, createdAt: opened,
                                      updatedAt: messages.first?.date ?? opened, link: URL(string: page),
                                      componentIDs: [], updates: messages))
            _ = affected
        }
        if let maint = result["maintenance"] as? [String: Any] {
            for m in maint["active"] as? [[String: Any]] ?? [] {
                let start = DateParse.iso(m["datetime_planned_start"] as? String) ?? Date()
                incidents.append(Incident(id: m["_id"] as? String ?? UUID().uuidString, name: m["name"] as? String ?? "Maintenance",
                                          status: "in_progress", impact: .maintenance, createdAt: start, updatedAt: start,
                                          link: URL(string: page), componentIDs: [], updates: [], isMaintenance: true))
            }
        }
        let overall = health((result["status_overall"] as? [String: Any])?["status_code"])
        return OfficialStatus(
            indicator: overall,
            description: (result["status_overall"] as? [String: Any])?["status"] as? String ?? overall.label,
            components: components, incidents: incidents,
            pageURL: URL(string: page) ?? URL(string: "https://status.io")!,
            fetchedAt: Date(), source: .statusio
        )
    }

    private func feed(_ base: String) async throws -> OfficialStatus? {
        try await feedAt(urls: ["/history.rss", "/feed.rss", "/history.atom", "/feed.atom", "/rss", "/feed"].map { base + $0 }, page: base)
    }

    private func feedAt(urls: [String], page base: String) async throws -> OfficialStatus? {
        for path in urls {
            guard let url = URL(string: path) else { continue }
            guard let fetched = try? await session.data(from: url) else { continue }
            let (data, resp) = fetched
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let head = String(data: data.prefix(400), encoding: .utf8),
                  head.contains("<rss") || head.contains("<feed") || head.contains("<?xml") else { continue }
            let items = FeedParser.parse(data)
            guard !items.isEmpty || head.contains("<rss") || head.contains("<feed") else { continue }

            // An item updated in the last 12 hours that doesn't read as finished is treated as live.
            let resolvedWords = ["resolved", "completed", "postmortem", "has been fixed", "operational", "monitoring"]
            let live = items.filter { item in
                guard let d = item.date, Date().timeIntervalSince(d) < 12 * 3600 else { return false }
                let text = (item.title + " " + item.summary).lowercased()
                return !resolvedWords.contains { text.contains($0) }
            }
            let incidents = live.prefix(3).enumerated().map { idx, item in
                Incident(id: "feed-\(idx)-\(item.title.hashValue)", name: item.title, status: "investigating", impact: .degraded,
                         createdAt: item.date ?? Date(), updatedAt: item.date ?? Date(), link: item.link,
                         componentIDs: [], updates: item.summary.isEmpty ? [] : [IncidentUpdate(status: "update", body: item.summary, date: item.date ?? Date())])
            }
            return OfficialStatus(
                indicator: incidents.isEmpty ? .operational : .degraded,
                description: incidents.isEmpty ? "No active incidents in feed" : "Active incident",
                components: [], incidents: Array(incidents),
                pageURL: URL(string: base)!, fetchedAt: Date(), source: .feed
            )
        }
        return nil
    }
}

// MARK: - Helpers

enum DateParse {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let rfc822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()
    private static let rfc822Zone: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    static func iso(_ s: String?) -> Date? {
        guard let s else { return nil }
        return fractional.date(from: s) ?? plain.date(from: s)
    }

    static func any(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return iso(t) ?? rfc822.date(from: t) ?? rfc822Zone.date(from: t)
    }
}

struct FeedItem {
    var title = ""
    var summary = ""
    var date: Date?
    var link: URL?
}

final class FeedParser: NSObject, XMLParserDelegate {
    private var items: [FeedItem] = []
    private var current: FeedItem?
    private var text = ""

    static func parse(_ data: Data) -> [FeedItem] {
        let p = FeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        parser.parse()
        return p.items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if name == "item" || name == "entry" { current = FeedItem() }
        if name == "link", current != nil, let href = attributes["href"] { current?.link = URL(string: href) }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard current != nil else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title": current?.title = value
        case "description", "summary", "content": current?.summary = String(Self.stripHTML(value).prefix(600))
        case "pubDate", "updated", "published": if current?.date == nil { current?.date = DateParse.any(value) }
        case "link": if current?.link == nil, !value.isEmpty { current?.link = URL(string: value) }
        case "item", "entry":
            if let c = current { items.append(c) }
            current = nil
        default: break
        }
    }

    static func stripHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
