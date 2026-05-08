import Foundation

struct MappingRule: Codable, Hashable, Identifiable {
    var host: String
    var pathPrefix: String?
    /// Local Chrome profile directory (e.g. "Profile 2"). Cached so legacy
    /// installs without `userName` keep working, and so resolution is fast
    /// when the rule was authored on this machine.
    var profile: String
    /// Google account email associated with the profile. Stable across
    /// devices: the same account typically lives in different local
    /// directories on different Macs, so we resolve by email at lookup time.
    /// Nil for profiles that aren't signed into Google or for rules saved
    /// before this field existed.
    var userName: String?

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

    /// Resolves a rule to a local profile directory. Prefers `userName`
    /// (stable across machines) and falls back to the cached `profile`
    /// directory when no email is recorded or the email isn't signed into
    /// any local profile. Returns nil when the rule has an email that
    /// doesn't match any local profile — safer to fall through to the
    /// picker than to silently route to the cached (and likely wrong)
    /// directory.
    static func resolveProfile(for rule: MappingRule, profiles: [ChromeProfile]) -> String? {
        if let email = rule.userName?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            let needle = email.lowercased()
            if let p = profiles.first(where: { $0.userName.lowercased() == needle }) {
                return p.directory
            }
            return nil
        }
        return rule.profile
    }

    func lookup(host: String, path: String, profiles: [ChromeProfile]) -> String? {
        let key = Self.normalize(host)
        let normalizedPath = path.isEmpty ? "/" : path
        if let r = bestMatch(host: key, path: normalizedPath) {
            return Self.resolveProfile(for: r, profiles: profiles)
        }
        // Parent-domain walk only applies to host-only rules; path prefixes
        // are intentionally tied to the exact host they were saved against.
        var parts = key.split(separator: ".").map(String.init)
        while parts.count > 2 {
            parts.removeFirst()
            let parent = parts.joined(separator: ".")
            if let r = rules.first(where: { $0.host == parent && ($0.pathPrefix?.isEmpty ?? true) }) {
                return Self.resolveProfile(for: r, profiles: profiles)
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

    mutating func set(host: String, pathPrefix: String?, profile: String, userName: String? = nil) {
        let h = Self.normalize(host)
        let p = Self.normalizePathPrefix(pathPrefix)
        let trimmedEmail = userName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (trimmedEmail?.isEmpty ?? true) ? nil : trimmedEmail
        if let idx = rules.firstIndex(where: { $0.host == h && $0.pathPrefix == p }) {
            rules[idx].profile = profile
            rules[idx].userName = email
        } else {
            rules.append(MappingRule(host: h, pathPrefix: p, profile: profile, userName: email))
        }
    }

    /// Backfill `userName` on legacy rules from the current machine's
    /// profile list so a future export carries portable identifiers.
    mutating func backfillUserNames(profiles: [ChromeProfile]) -> Bool {
        var changed = false
        for i in rules.indices where rules[i].userName?.isEmpty ?? true {
            if let p = profiles.first(where: { $0.directory == rules[i].profile }),
               !p.userName.isEmpty {
                rules[i].userName = p.userName
                changed = true
            }
        }
        return changed
    }

    mutating func remove(host: String, pathPrefix: String?) {
        let h = Self.normalize(host)
        let p = Self.normalizePathPrefix(pathPrefix)
        rules.removeAll { $0.host == h && $0.pathPrefix == p }
    }
}
