import Foundation

struct ChromeProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let userName: String
    let gaiaName: String
    let avatarFillARGB: UInt32?
    let avatarStrokeARGB: UInt32?
    let highlightARGB: UInt32?
    let avatarImageURL: URL?

    var directory: String { id }
}

enum ChromeProfiles {
    static func chromeRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    }

    static func localStatePath() -> URL {
        chromeRoot().appendingPathComponent("Local State")
    }

    static func load() -> [ChromeProfile] {
        guard let data = try? Data(contentsOf: localStatePath()),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]] else {
            return []
        }
        let profiles: [ChromeProfile] = cache.map { dir, info in
            ChromeProfile(
                id: dir,
                name: info["name"] as? String ?? dir,
                userName: info["user_name"] as? String ?? "",
                gaiaName: info["gaia_name"] as? String ?? "",
                avatarFillARGB: argb(info["default_avatar_fill_color"]),
                avatarStrokeARGB: argb(info["default_avatar_stroke_color"]),
                highlightARGB: argb(info["profile_highlight_color"]),
                avatarImageURL: gaiaPicture(dir: dir, name: info["gaia_picture_file_name"] as? String)
            )
        }
        return profiles.sorted { a, b in
            if a.directory == "Default" { return true }
            if b.directory == "Default" { return false }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private static func argb(_ value: Any?) -> UInt32? {
        guard let n = value as? Int else { return nil }
        return UInt32(bitPattern: Int32(truncatingIfNeeded: n))
    }

    private static func gaiaPicture(dir: String, name: String?) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        let candidate = chromeRoot()
            .appendingPathComponent(dir, isDirectory: true)
            .appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}
