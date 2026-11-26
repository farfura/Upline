import Foundation
import Network

/// Talks to the real API hosts, because status pages are often late.
enum Prober {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.timeoutIntervalForResource = 10
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.httpAdditionalHeaders = ["User-Agent": "Upline/1.0 (reachability probe)"]
        c.waitsForConnectivity = false
        c.httpShouldSetCookies = false
        return URLSession(configuration: c)
    }()

    /// Gateway and origin errors that mean "the service is not answering".
    static let failingCodes: Set<Int> = [502, 503, 504, 520, 521, 522, 523, 524, 525, 526, 527, 530]

    static func probe(_ target: String) async -> ProbeSample {
        if target.hasPrefix("tcp://") { return await tcp(target) }
        return await http(target)
    }

    private static func http(_ target: String) async -> ProbeSample {
        guard let url = URL(string: target) else { return ProbeSample(date: Date(), latencyMs: nil, ok: false, detail: "Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let start = DispatchTime.now()
        do {
            let (_, resp) = try await session.data(for: req)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if failingCodes.contains(code) {
                return ProbeSample(date: Date(), latencyMs: ms, ok: false, detail: "HTTP \(code)")
            }
            return ProbeSample(date: Date(), latencyMs: ms, ok: true, detail: "HTTP \(code)")
        } catch let e as URLError {
            return ProbeSample(date: Date(), latencyMs: nil, ok: false, detail: describe(e))
        } catch {
            return ProbeSample(date: Date(), latencyMs: nil, ok: false, detail: error.localizedDescription)
        }
    }

    static func describe(_ e: URLError) -> String {
        switch e.code {
        case .timedOut: "Timed out"
        case .cannotFindHost, .dnsLookupFailed: "DNS lookup failed"
        case .cannotConnectToHost: "Connection refused"
        case .networkConnectionLost: "Connection dropped"
        case .notConnectedToInternet: "Offline"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid:
            "TLS handshake failed"
        default: e.localizedDescription
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    /// Opens a TCP connection (database and cache hosts) and measures time to ready.
    static func tcp(_ target: String) async -> ProbeSample {
        let rest = target.dropFirst("tcp://".count)
        guard let colon = rest.lastIndex(of: ":"), let port = UInt16(rest[rest.index(after: colon)...]),
              let nwPort = NWEndpoint.Port(rawValue: port) else {
            return ProbeSample(date: Date(), latencyMs: nil, ok: false, detail: "Bad target")
        }
        let host = String(rest[..<colon])
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let start = DispatchTime.now()
        let once = Once()
        let queue = DispatchQueue(label: "upline.tcp")

        return await withCheckedContinuation { cont in
            func finish(_ ok: Bool, _ detail: String) {
                guard once.claim() else { return }
                let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                conn.cancel()
                cont.resume(returning: ProbeSample(date: Date(), latencyMs: ok ? ms : nil, ok: ok, detail: detail))
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true, "TCP open")
                case .failed(let e): finish(false, "TCP failed: \(e.localizedDescription)")
                case .waiting(let e): finish(false, "TCP waiting: \(e.localizedDescription)")
                default: break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 7) { finish(false, "Timed out") }
        }
    }
}

// MARK: - Deep check

/// Uses the key from the project's own .env, in memory only, sent only to that service's host.
enum AuthChecker {
    static func readKey(names: [String], in projects: [Project]) -> String? {
        let fm = FileManager.default
        for project in projects {
            var files: [String] = [".env.local", ".env", ".env.development.local", ".env.development"]
            // Also look where the scanner saw env files.
            for d in project.detections {
                for ev in d.evidence {
                    if let colon = ev.firstIndex(of: ":") {
                        let rel = String(ev[..<colon])
                        if (rel as NSString).lastPathComponent.hasPrefix(".env"), !rel.contains("example") { files.append(rel) }
                    }
                }
            }
            for rel in Array(NSOrderedSet(array: files)) as? [String] ?? files {
                let path = (project.path as NSString).appendingPathComponent(rel)
                guard fm.fileExists(atPath: path), let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                for line in text.split(whereSeparator: \.isNewline) {
                    var l = line.trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("export ") { l = String(l.dropFirst(7)) }
                    guard let eq = l.firstIndex(of: "=") else { continue }
                    let key = l[..<eq].trimmingCharacters(in: .whitespaces)
                    guard names.contains(key) else { continue }
                    let value = l[l.index(after: eq)...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !value.isEmpty, !value.contains("your_"), !value.contains("xxx"), !value.contains("<") { return value }
                }
            }
        }
        return nil
    }

    static func check(_ spec: AuthCheck, projects: [Project]) async -> AuthState {
        guard let key = readKey(names: spec.envKeys, in: projects) else { return .noKey }
        guard let url = URL(string: spec.url) else { return .failed("Bad check URL") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue(spec.valuePrefix + key, forHTTPHeaderField: spec.header)
        for (k, v) in spec.extraHeaders ?? [:] { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, resp) = try await Prober.session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data.prefix(4000), encoding: .utf8)?.lowercased() ?? ""
            let creditWords = ["credit balance", "insufficient_quota", "insufficient balance", "insufficient credits", "billing", "quota exceeded"]
            switch code {
            case 200..<300:
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // OpenRouter /key reports remaining credit.
                    if let d = json["data"] as? [String: Any], let remaining = d["limit_remaining"] as? Double, remaining <= 0 { return .noCredits }
                    // GitHub /rate_limit.
                    if let core = (json["resources"] as? [String: Any])?["core"] as? [String: Any], let rem = core["remaining"] as? Int, rem == 0 { return .rateLimited }
                }
                return .ok
            case 401, 403:
                return creditWords.contains(where: { body.contains($0) }) ? .noCredits : .invalidKey
            case 402: return .noCredits
            case 429: return creditWords.contains(where: { body.contains($0) }) ? .noCredits : .rateLimited
            case 400 where creditWords.contains(where: { body.contains($0) }): return .noCredits
            default: return .failed("Check returned \(code)")
            }
        } catch let e as URLError {
            return .failed(Prober.describe(e))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

// MARK: - Is it me?

enum LocalNetwork: Equatable {
    case online
    case offline
    case dnsBroken
    case captivePortal
    case checking

    var problem: String? {
        switch self {
        case .offline: "You're offline. Services can't be checked until you reconnect."
        case .dnsBroken: "Your DNS isn't resolving. The internet works, names don't."
        case .captivePortal: "This Wi-Fi wants you to sign in before anything works."
        default: nil
        }
    }
}

enum Connectivity {
    /// Checks raw IP reachability and name resolution separately so we can say whose fault it is.
    static func diagnose() async -> LocalNetwork {
        async let ip1 = Prober.tcp("tcp://1.1.1.1:443")
        async let ip2 = Prober.tcp("tcp://8.8.8.8:443")
        let (a, b) = await (ip1, ip2)
        let ipOK = a.ok || b.ok

        var req = URLRequest(url: URL(string: "http://captive.apple.com/hotspot-detect.html")!)
        req.timeoutInterval = 6
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let page = try? await Prober.session.data(for: req)

        if let page, let body = String(data: page.0, encoding: .utf8) {
            return body.contains("Success") ? .online : .captivePortal
        }
        return ipOK ? .dnsBroken : .offline
    }
}
