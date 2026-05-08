import Foundation

struct UpdateInfo {
    let version: String
    let releaseURL: URL
}

enum Updater {
    private static let releasesURL = URL(string: "https://api.github.com/repos/dpovey/chrome-dispatch/releases/latest")!

    static func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Hits the GitHub API for the latest release. Returns the new version
    /// only when it's strictly newer than the running app; nil on no-update
    /// or transient failure. Failures are logged but never surfaced — a
    /// blip in connectivity shouldn't trigger a user-facing dialog.
    static func checkForUpdate() async -> UpdateInfo? {
        var req = URLRequest(url: releasesURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                NSLog("Chrome Dispatch: update check HTTP \(((response as? HTTPURLResponse)?.statusCode).map(String.init) ?? "?")")
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let urlString = json["html_url"] as? String,
                  let url = URL(string: urlString) else {
                NSLog("Chrome Dispatch: update check unexpected payload")
                return nil
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            return isNewer(latest, than: currentVersion()) ? UpdateInfo(version: latest, releaseURL: url) : nil
        } catch {
            NSLog("Chrome Dispatch: update check failed: \(error)")
            return nil
        }
    }

    /// Component-wise numeric compare: 0.10.0 > 0.2.0. Trailing non-numeric
    /// suffixes (-rc, -beta) are dropped from each component before parse.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = parseComponents(a)
        let pb = parseComponents(b)
        for i in 0..<max(pa.count, pb.count) {
            let av = i < pa.count ? pa[i] : 0
            let bv = i < pb.count ? pb[i] : 0
            if av != bv { return av > bv }
        }
        return false
    }

    private static func parseComponents(_ s: String) -> [Int] {
        s.split(separator: ".").map { part in
            Int(part.prefix(while: { $0.isNumber })) ?? 0
        }
    }
}
