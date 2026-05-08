import Foundation

struct MappingRule: Codable, Hashable, Identifiable {
    var host: String
    var pathPrefix: String?
    var profile: String

    var id: String { "\(host)\(pathPrefix ?? "")" }

    var displayKey: String {
        if let p = pathPrefix, !p.isEmpty { return host + p }
        return host
    }
}

struct Mappings: Codable {
    var rules: [MappingRule] = []

    private enum CodingKeys: String, CodingKey {
        case rules, entries
    }

    init() {}

    init(rules: [MappingRule]) { self.rules = rules }

    /// Decoder accepts both the current `rules` array and the legacy
    /// `entries` dictionary so existing installs migrate transparently.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let r = try? c.decode([MappingRule].self, forKey: .rules) {
            self.rules = r
        } else if let e = try? c.decode([String: String].self, forKey: .entries) {
            self.rules = e
                .sorted(by: { $0.key < $1.key })
                .map { MappingRule(host: $0.key, pathPrefix: nil, profile: $0.value) }
        } else {
            self.rules = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rules, forKey: .rules)
    }

    static func storageURL() throws -> URL {
        let support = try FileManager.default
            .url(for: .applicationSupportDirectory,
                 in: .userDomainMask,
                 appropriateFor: nil,
                 create: true)
            .appendingPathComponent("ChromeDispatch", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("mappings.json")
    }

    static func load() -> Mappings {
        do {
            let url = try storageURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return Mappings() }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Mappings.self, from: data)
        } catch {
            NSLog("Chrome Dispatch: failed to load mappings: \(error)")
            return Mappings()
        }
    }

    @discardableResult
    func save() -> Bool {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(self)
            try data.write(to: try Self.storageURL(), options: .atomic)
            return true
        } catch {
            NSLog("Chrome Dispatch: failed to save mappings: \(error)")
            return false
        }
    }

    /// Hostnames are case-insensitive in DNS — store and look up in a normalized form.
    static func normalize(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Returns nil for empty/"/" input so a missing prefix and an explicit
    /// root prefix collapse to the same "match all paths" rule. Ensures a
    /// leading "/" and strips trailing slashes for stable comparison.
    static func normalizePathPrefix(_ p: String?) -> String? {
        guard var s = p?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if !s.hasPrefix("/") { s = "/" + s }
        while s.count > 1, s.hasSuffix("/") { s.removeLast() }
        return s == "/" ? nil : s
    }

    func lookup(host: String, path: String) -> String? {
        let key = Self.normalize(host)
        let normalizedPath = path.isEmpty ? "/" : path
        if let r = bestMatch(host: key, path: normalizedPath) { return r.profile }
        // Parent-domain walk only applies to host-only rules; path prefixes
        // are intentionally tied to the exact host they were saved against.
        var parts = key.split(separator: ".").map(String.init)
        while parts.count > 2 {
            parts.removeFirst()
            let parent = parts.joined(separator: ".")
            if let r = rules.first(where: { $0.host == parent && ($0.pathPrefix?.isEmpty ?? true) }) {
                return r.profile
            }
        }
        return nil
    }

    private func bestMatch(host: String, path: String) -> MappingRule? {
        var best: MappingRule?
        var bestScore = -1
        for r in rules where r.host == host {
            let prefix = r.pathPrefix ?? ""
            let matches = prefix.isEmpty || pathMatches(path: path, prefix: prefix)
            if !matches { continue }
            let score = prefix.count
            if score > bestScore {
                best = r
                bestScore = score
            }
        }
        return best
    }

    /// Match on segment boundaries so `/foo` does not also match `/foobar`.
    private func pathMatches(path: String, prefix: String) -> Bool {
        guard path.hasPrefix(prefix) else { return false }
        if path.count == prefix.count { return true }
        let next = path[path.index(path.startIndex, offsetBy: prefix.count)]
        return next == "/"
    }

    mutating func set(host: String, pathPrefix: String?, profile: String) {
        let h = Self.normalize(host)
        let p = Self.normalizePathPrefix(pathPrefix)
        if let idx = rules.firstIndex(where: { $0.host == h && $0.pathPrefix == p }) {
            rules[idx].profile = profile
        } else {
            rules.append(MappingRule(host: h, pathPrefix: p, profile: profile))
        }
    }

    mutating func remove(host: String, pathPrefix: String?) {
        let h = Self.normalize(host)
        let p = Self.normalizePathPrefix(pathPrefix)
        rules.removeAll { $0.host == h && $0.pathPrefix == p }
    }
}
