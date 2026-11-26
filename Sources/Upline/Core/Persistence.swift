import Foundation

enum Persistence {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Upline", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var configURL: URL { directory.appendingPathComponent("config.json") }
    private static var projectsURL: URL { directory.appendingPathComponent("projects.json") }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func loadConfig() -> Config {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? decoder.decode(Config.self, from: data) else { return Config() }
        return config
    }

    static func save(_ config: Config) {
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    static func loadProjects() -> [Project] {
        guard let data = try? Data(contentsOf: projectsURL),
              let projects = try? decoder.decode([Project].self, from: data) else { return [] }
        return projects
    }

    static func save(_ projects: [Project]) {
        guard let data = try? encoder.encode(projects) else { return }
        try? data.write(to: projectsURL, options: .atomic)
    }
}
