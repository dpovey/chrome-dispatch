import SwiftUI
import AppKit

extension Color {
    init?(argb: UInt32?) {
        guard let argb else { return nil }
        let alpha = Double((argb >> 24) & 0xFF) / 255.0
        let red   = Double((argb >> 16) & 0xFF) / 255.0
        let green = Double((argb >>  8) & 0xFF) / 255.0
        let blue  = Double( argb        & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha == 0 ? 1 : alpha)
    }

    /// Approx perceived luminance, 0–1, sRGB-corrected. Treats nil/transparent as mid-gray.
    var perceivedLuminance: Double {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        let r = Double(ns.redComponent), g = Double(ns.greenComponent), b = Double(ns.blueComponent)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

extension ChromeProfile {
    /// Color for a colored ring or chip. Falls back to a deterministic palette colour if
    /// the stored highlight is the near-black neutral Chrome uses for unstyled profiles.
    var themeColor: Color {
        if let argb = highlightARGB, let c = Color(argb: argb), c.perceivedLuminance > 0.10 {
            return c
        }
        if let argb = avatarFillARGB, let c = Color(argb: argb), c.perceivedLuminance > 0.10 {
            return c
        }
        let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .red]
        var hash = 5381
        for ch in directory.unicodeScalars { hash = ((hash << 5) &+ hash) &+ Int(ch.value) }
        return palette[abs(hash) % palette.count]
    }

    var initials: String {
        let source = !gaiaName.isEmpty ? gaiaName : name
        let parts = source.split(separator: " ")
        if parts.count >= 2, let a = parts.first?.first, let b = parts.dropFirst().first?.first {
            return "\(a)\(b)".uppercased()
        }
        return String(source.prefix(2)).uppercased()
    }
}

enum ProfileImageCache {
    private static var cache: [String: NSImage] = [:]

    static func image(for profile: ChromeProfile) -> NSImage? {
        if let cached = cache[profile.directory] { return cached }
        guard let url = profile.avatarImageURL,
              let img = NSImage(contentsOf: url) else { return nil }
        cache[profile.directory] = img
        return img
    }
}

struct ProfileAvatar: View {
    let profile: ChromeProfile
    var size: CGFloat = 36
    var ringWidth: CGFloat = 2

    var body: some View {
        let ring = profile.themeColor
        ZStack {
            Circle().fill(ring.opacity(0.18))

            if let img = ProfileImageCache.image(for: profile) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size - ringWidth * 2 - 2,
                           height: size - ringWidth * 2 - 2)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(ring)
                    .frame(width: size - ringWidth * 2 - 2,
                           height: size - ringWidth * 2 - 2)
                    .overlay(
                        Text(profile.initials)
                            .font(.system(size: size * 0.38, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .overlay(
            Circle().strokeBorder(ring, lineWidth: ringWidth)
        )
        .frame(width: size, height: size)
    }
}

struct ProfileColorDot: View {
    let profile: ChromeProfile
    var size: CGFloat = 12

    var body: some View {
        Circle()
            .fill(profile.themeColor)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
    }
}
