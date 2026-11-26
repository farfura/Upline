import Foundation

struct ScanProgress: Sendable {
    var reposFound = 0
    var reposScanned = 0
    var servicesFound = 0
    var currentPath = ""
    var lastHits: [String] = []
}

/// Walks the user's code folders, finds git repos and works out which third party
/// services each one talks to. It reads env *keys* and *hosts*, never secret values.
struct ProjectScanner: Sendable {
    let catalog: [CatalogEntry]

    static let skipDirs: Set<String> = [
        "node_modules", ".git", "build", "dist", "out", ".next", ".nuxt", ".svelte-kit", ".turbo", ".vercel",
        "Pods", "DerivedData", ".build", ".swiftpm", "vendor", "target", ".venv", "venv", "env", "__pycache__",
        ".cache", ".gradle", ".idea", ".expo", "coverage", "Library", "Applications", ".Trash", "tmp", ".terraform",
        "ios", "android", // native shells of RN projects are scanned only for Podfile/gradle at depth below
    ]

    static let sourceExtensions: Set<String> = ["ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "go", "swift", "kt", "rb", "php", "dart", "rs"]

    // MARK: Repo discovery

    func findRepos(roots: [String], ignored: Set<String>, maxDepth: Int = 4) -> [URL] {
        var repos: [URL] = []
        var seen = Set<String>()
        let fm = FileManager.default

        func visit(_ url: URL, depth: Int) {
            if repos.count > 400 { return }
            let gitPath = url.appendingPathComponent(".git").path
            if fm.fileExists(atPath: gitPath) {
                let key = url.standardizedFileURL.path
                if !ignored.contains(key), seen.insert(key.lowercased()).inserted { repos.append(url) }
                return
            }
            guard depth < maxDepth,
                  let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            else { return }
            for child in children {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                if Self.skipDirs.contains(child.lastPathComponent) || child.pathExtension == "app" { continue }
                visit(child, depth: depth + 1)
            }
        }

        for root in roots {
            visit(URL(fileURLWithPath: root.expandingTilde), depth: 0)
        }
        return repos.sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
    }

    // MARK: One repo

    private final class Accumulator {
        var evidence: [String: [String]] = [:]
        var regions: [String: Set<String>] = [:]
        var probeHosts: [String: Set<String>] = [:]
        var customHosts: [String: String] = [:]   // host -> evidence
        var stack = Set<String>()
        var latest: Date = .distantPast

        func hit(_ id: String, _ why: String) {
            var list = evidence[id, default: []]
            if !list.contains(why), list.count < 8 { list.append(why) }
            evidence[id] = list
        }
    }

    func scan(repo: URL) -> Project {
        let acc = Accumulator()
        let fm = FileManager.default
        var sourceBudget = 500

        func walk(_ dir: URL, depth: Int) {
            guard depth <= 5,
                  let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey], options: [])
            else { return }
            for child in children {
                let name = child.lastPathComponent
                let v = try? child.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey])
                if v?.isSymbolicLink == true { continue }
                if v?.isDirectory == true {
                    if name == "ios" || name == "android" {
                        // Only look for native manifests inside, one level.
                        walkNativeShell(child)
                        continue
                    }
                    if Self.skipDirs.contains(name) || (name.hasPrefix(".") && name != ".github") { continue }
                    walk(child, depth: depth + 1)
                    continue
                }
                if let m = v?.contentModificationDate, m > acc.latest, !name.hasPrefix(".DS_") { acc.latest = m }
                let size = v?.fileSize ?? 0
                guard size < 600_000 else { continue }
                let rel = String(child.path.dropFirst(repo.path.count + 1))
                inspect(file: child, name: name, rel: rel, acc: acc, sourceBudget: &sourceBudget)
            }
        }

        func walkNativeShell(_ dir: URL) {
            for name in ["Podfile", "build.gradle", "build.gradle.kts", "app/build.gradle", "app/build.gradle.kts"] {
                let f = dir.appendingPathComponent(name)
                if fm.fileExists(atPath: f.path) {
                    var budget = 0
                    inspect(file: f, name: f.lastPathComponent, rel: String(f.path.dropFirst(repo.path.count + 1)), acc: acc, sourceBudget: &budget)
                }
            }
        }

        walk(repo, depth: 0)
        readGit(repo: repo, acc: acc)

        var detections = acc.evidence.keys.sorted().map { id in
            Detection(
                serviceID: id,
                evidence: acc.evidence[id] ?? [],
                regions: Array(acc.regions[id] ?? []).sorted(),
                hosts: Array(acc.probeHosts[id] ?? []).sorted()
            )
        }
        // Hosts we don't know become custom services, watched by probe only.
        for (host, why) in acc.customHosts.sorted(by: { $0.key < $1.key }).prefix(12) {
            detections.append(Detection(serviceID: "host:\(host)", evidence: [why], regions: Self.regions(in: host), hosts: ["https://\(host)"]))
        }
        return Project(
            name: repo.lastPathComponent,
            path: repo.path,
            detections: detections,
            lastActivity: acc.latest == .distantPast ? nil : acc.latest,
            stack: Array(acc.stack).sorted()
        )
    }

    // MARK: File inspection

    private func inspect(file: URL, name: String, rel: String, acc: Accumulator, sourceBudget: inout Int) {
        let lower = name.lowercased()
        let isCompose = (lower.hasPrefix("docker-compose") || lower.hasPrefix("compose")) && (lower.hasSuffix(".yml") || lower.hasSuffix(".yaml"))
        let isPython = (lower.hasPrefix("requirements") && lower.hasSuffix(".txt")) || ["pyproject.toml", "Pipfile", "setup.py"].contains(name)
        let manifests: Set<String> = ["Podfile", "Gemfile", "pubspec.yaml", "go.mod", "Cargo.toml", "build.gradle", "build.gradle.kts", "Package.swift", "composer.json"]
        let configHints: [String: String] = [
            "wrangler.toml": "cloudflare", "wrangler.jsonc": "cloudflare", "vercel.json": "vercel", "netlify.toml": "netlify",
            "fly.toml": "fly", "railway.json": "railway", "railway.toml": "railway", "render.yaml": "render", "eas.json": "expo",
            "firebase.json": "firebase", "GoogleService-Info.plist": "firebase", "google-services.json": "firebase",
            "sentry.properties": "sentry",
        ]

        if name == "package.json" {
            parsePackageJSON(file, rel: rel, acc: acc)
            acc.hit("npm", rel)
        } else if isPython {
            parseManifestTokens(file, rel: rel, acc: acc)
            acc.hit("pypi", rel)
            acc.stack.insert("Python")
        } else if manifests.contains(name) {
            parseManifestTokens(file, rel: rel, acc: acc)
            let stackNames = ["go.mod": "Go", "Package.swift": "Swift", "pubspec.yaml": "Flutter", "Gemfile": "Ruby", "Cargo.toml": "Rust"]
            if let tech = stackNames[name] { acc.stack.insert(tech) }
        } else if name == "Dockerfile" || lower.hasSuffix(".dockerfile") {
            acc.hit("dockerhub", rel)
            acc.stack.insert("Docker")
        } else if isCompose {
            acc.hit("dockerhub", rel)
            acc.stack.insert("Docker")
            parseSourceHosts(file, rel: rel, acc: acc)
        } else if name == ".env" || name.hasPrefix(".env.") || name.hasSuffix(".env") {
            parseEnv(file, rel: rel, acc: acc)
        } else if let id = configHints[name] {
            acc.hit(id, rel)
        } else if name.hasPrefix("sentry.") && name.hasSuffix(".config.ts") {
            acc.hit("sentry", rel)
        } else if Self.sourceExtensions.contains(file.pathExtension.lowercased()), sourceBudget > 0 {
            sourceBudget -= 1
            parseSourceHosts(file, rel: rel, acc: acc)
        }
    }

    // MARK: Matchers

    private func matchPackage(_ name: String) -> [String] {
        var ids: [String] = []
        for entry in catalog {
            for p in entry.packages {
                let hit = p.hasSuffix("*") ? name.hasPrefix(String(p.dropLast())) : name == p
                if hit { ids.append(entry.id); break }
            }
        }
        return ids
    }

    private func matchEnvKey(_ key: String) -> [String] {
        catalog.filter { e in e.envKeys.contains { key.hasPrefix($0) } }.map(\.id)
    }

    private func matchHost(_ host: String) -> CatalogEntry? {
        let h = host.lowercased()
        var best: (CatalogEntry, Int)?
        for e in catalog {
            for suffix in e.hosts where h == suffix || h.hasSuffix("." + suffix) {
                if best == nil || suffix.count > best!.1 { best = (e, suffix.count) }
            }
        }
        return best?.0
    }

    static let regionRegex = try! NSRegularExpression(
        pattern: #"(?:^|[.\-])((?:us|eu|ap|sa|ca|me|af|il|mx)-(?:east|west|central|north|south|southeast|northeast|northwest|southwest)-\d)"#
    )

    static func regions(in host: String) -> [String] {
        let ns = host as NSString
        return regionRegex.matches(in: host, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    private static let ignoredHostSuffixes = [
        "localhost", "local", "internal", "lan", "test", "example.com", "example.org", "w3.org", "schema.org", "json-schema.org",
        "github.com", "githubusercontent.com", "npmjs.com", "npmjs.org", "googleapis.com", "gstatic.com", "google.com",
        "apple.com", "mozilla.org", "reactjs.org", "react.dev", "nextjs.org", "vercel.com", "unpkg.com", "jsdelivr.net",
        "cdnjs.cloudflare.com", "fonts.googleapis.com", "twitter.com", "x.com", "facebook.com", "linkedin.com", "youtube.com",
        "wikipedia.org", "stackoverflow.com", "medium.com", "docs.rs", "readthedocs.io", "shields.io", "img.shields.io",
    ]

    private func isIgnorableHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h.first?.isNumber == true { return true } // raw IPs
        if !h.contains(".") { return true }
        return Self.ignoredHostSuffixes.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    /// Records a host: either for a known service (with a probe target and region) or as a custom service.
    private func record(host rawHost: String, scheme: String, port: Int?, why: String, acc: Accumulator, allowCustom: Bool) {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty, !host.contains("{"), !host.contains("$") else { return }
        if let entry = matchHost(host) {
            acc.hit(entry.id, why)
            for r in Self.regions(in: host) { acc.regions[entry.id, default: []].insert(r) }
            if let target = probeTarget(host: host, scheme: scheme, port: port) {
                var set = acc.probeHosts[entry.id, default: []]
                if set.count < 3 { set.insert(target) }
                acc.probeHosts[entry.id] = set
            }
            return
        }
        guard allowCustom, !isIgnorableHost(host), scheme.hasPrefix("http") || scheme.isEmpty else { return }
        if acc.customHosts[host] == nil { acc.customHosts[host] = why }
    }

    private func probeTarget(host: String, scheme: String, port: Int?) -> String? {
        switch scheme {
        case "postgres", "postgresql": return "tcp://\(host):\(port ?? 5432)"
        case "redis", "rediss": return "tcp://\(host):\(port ?? 6379)"
        case "mysql": return "tcp://\(host):\(port ?? 3306)"
        case "mongodb": return "tcp://\(host):\(port ?? 27017)"
        case "mongodb+srv", "libsql", "wss", "ws": return nil
        case "https", "http": return "https://\(host)"
        default: return nil
        }
    }

    // MARK: Parsers

    private func parsePackageJSON(_ file: URL, rel: String, acc: Accumulator) {
        guard let data = try? Data(contentsOf: file),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var deps: [String] = []
        for key in ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"] {
            if let d = obj[key] as? [String: Any] { deps.append(contentsOf: d.keys) }
        }
        let depSet = Set(deps)
        for dep in deps {
            for id in matchPackage(dep) { acc.hit(id, "\(rel): \(dep)") }
        }
        if depSet.contains("next") { acc.stack.insert("Next.js") }
        if depSet.contains("@nestjs/core") { acc.stack.insert("NestJS") }
        if depSet.contains("react-native") { acc.stack.insert("React Native") }
        if depSet.contains("expo") { acc.stack.insert("Expo") }
        if depSet.contains("express") { acc.stack.insert("Express") }
        if depSet.contains("vite") { acc.stack.insert("Vite") }
        if depSet.contains("svelte") { acc.stack.insert("Svelte") }
        if depSet.contains("vue") { acc.stack.insert("Vue") }
        if depSet.contains("electron") { acc.stack.insert("Electron") }
        if depSet.contains("prisma") || depSet.contains("@prisma/client") { acc.stack.insert("Prisma") }
        if depSet.contains("typescript") { acc.stack.insert("TypeScript") }
    }

    private static let tokenRegex = try! NSRegularExpression(pattern: #"[A-Za-z0-9@_./*\-]+"#)

    private func parseManifestTokens(_ file: URL, rel: String, acc: Accumulator) {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        let ns = text as NSString
        var seen = Set<String>()
        for m in Self.tokenRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var token = ns.substring(with: m.range)
            token = token.trimmingCharacters(in: CharacterSet(charactersIn: ".-/"))
            guard token.count > 2, seen.insert(token).inserted else { continue }
            for id in matchPackage(token) { acc.hit(id, "\(rel): \(token)") }
            // Pod subspecs like Firebase/Analytics
            if let base = token.split(separator: "/").first, base.count > 2, String(base) != token {
                for id in matchPackage(String(base)) { acc.hit(id, "\(rel): \(token)") }
            }
        }
        parseSourceHosts(file, rel: rel, acc: acc, allowCustom: false)
    }

    private static let customKeyHints = ["API", "URL", "ENDPOINT", "HOST", "BASE", "RPC", "SERVER"]
    private static let customKeyBlocks = ["CALLBACK", "REDIRECT", "ORIGIN", "SITE", "APP_URL", "FRONTEND", "PUBLIC_URL", "WEBHOOK", "RETURN", "CORS", "DOCS", "LOGO", "IMAGE", "CDN"]

    private func parseEnv(_ file: URL, rel: String, acc: Accumulator) {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        let isExample = rel.lowercased().contains("example") || rel.lowercased().contains("sample") || rel.lowercased().contains("template")
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { continue }

            for id in matchEnvKey(key) { acc.hit(id, "\(rel): \(key)") }

            // Only the host of URL values is used. The value itself is never stored.
            guard value.contains("://"), let comps = URLComponents(string: value), let host = comps.host else { continue }
            let allowCustom = !isExample
                && Self.customKeyHints.contains { key.contains($0) }
                && !Self.customKeyBlocks.contains { key.contains($0) }
            record(host: host, scheme: (comps.scheme ?? "").lowercased(), port: comps.port, why: "\(rel): \(key) → \(host)", acc: acc, allowCustom: allowCustom)
        }
    }

    private static let urlRegex = try! NSRegularExpression(pattern: #"\b(https?|wss?|postgres(?:ql)?|rediss?)://([A-Za-z0-9.\-]+\.[A-Za-z]{2,})(?::(\d{2,5}))?"#)

    private func parseSourceHosts(_ file: URL, rel: String, acc: Accumulator, allowCustom: Bool = true) {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        let ns = text as NSString
        for m in Self.urlRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).prefix(60) {
            let scheme = ns.substring(with: m.range(at: 1)).lowercased()
            let host = ns.substring(with: m.range(at: 2))
            let port = m.range(at: 3).location != NSNotFound ? Int(ns.substring(with: m.range(at: 3))) : nil
            // Hardcoded hosts in code count as custom services only when they look like an API.
            let looksLikeAPI = host.lowercased().hasPrefix("api.") || host.lowercased().contains(".api.")
            record(host: host, scheme: scheme, port: port, why: "\(rel) → \(host)", acc: acc, allowCustom: allowCustom && looksLikeAPI)
        }
    }

    private func readGit(repo: URL, acc: Accumulator) {
        let git = repo.appendingPathComponent(".git")
        let fm = FileManager.default
        for name in ["index", "HEAD", "FETCH_HEAD", "logs/HEAD"] {
            if let d = (try? fm.attributesOfItem(atPath: git.appendingPathComponent(name).path))?[.modificationDate] as? Date, d > acc.latest {
                acc.latest = d
            }
        }
        guard let config = try? String(contentsOf: git.appendingPathComponent("config"), encoding: .utf8) else { return }
        if config.contains("github.com") { acc.hit("github", "git remote") }
        if config.contains("gitlab.com") { acc.hit("gitlab", "git remote") }
        if config.contains("bitbucket.org") { acc.hit("bitbucket", "git remote") }
    }
}
