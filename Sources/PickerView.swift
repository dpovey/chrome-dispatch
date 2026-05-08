import SwiftUI

struct PickerSelection {
    let profile: ChromeProfile
    let remember: Bool
    let pathPrefix: String?
}

struct PickerView: View {
    let url: String
    let host: String
    let path: String
    let profiles: [ChromeProfile]
    let onChoice: (PickerSelection?) -> Void

    @State private var remember: Bool = true
    @State private var advancedExpanded: Bool = false
    @State private var selectedPathPrefix: String? = nil
    @State private var hovered: ChromeProfile.ID?

    /// Cumulative prefixes built from the URL's path:
    /// `/a/b/c` → ["/a", "/a/b", "/a/b/c"]
    private var pathPrefixOptions: [String] {
        let segments = path.split(separator: "/").map(String.init)
        var result: [String] = []
        var acc = ""
        for seg in segments where !seg.isEmpty {
            acc += "/" + seg
            result.append(acc)
        }
        return result
    }

    private var resolvedPathPrefix: String? {
        Mappings.normalizePathPrefix(selectedPathPrefix)
    }

    private var rememberLabel: String {
        if let p = resolvedPathPrefix { return "Remember choice for \(host)\(p)" }
        return "Remember choice for \(host)"
    }

    /// File URLs and other host-less schemes can't be persisted as a mapping
    /// (the lookup keys on host), so suppress the remember UI in that case.
    private var canRemember: Bool { !host.isEmpty }

    private var locationLabel: String {
        if !host.isEmpty { return host + (path.isEmpty ? "" : path) }
        if let u = URL(string: url), u.isFileURL { return u.lastPathComponent }
        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Open in Chrome")
                    .font(.title3.weight(.semibold))
                Text(locationLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url)
            }

            if canRemember {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(rememberLabel, isOn: $remember)
                        .toggleStyle(.checkbox)

                    DisclosureGroup(isExpanded: $advancedExpanded) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Match level")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker(selection: $selectedPathPrefix) {
                                Text("All paths on \(host)").tag(String?.none)
                                ForEach(pathPrefixOptions, id: \.self) { opt in
                                    Text(host + opt)
                                        .tag(String?.some(opt))
                                }
                            } label: {
                                EmptyView()
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                        }
                        .padding(.top, 6)
                        .disabled(!remember)
                    } label: {
                        Text("Advanced")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(!remember)
                }
            }

            VStack(spacing: 8) {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    profileButton(for: profile, index: index)
                }
            }

            HStack {
                if profiles.count > 1 {
                    Text("⏎ first profile · 1–\(min(profiles.count, 9)) by number · ⎋ cancel")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Cancel") { onChoice(nil) }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: advancedExpanded) { _, isOpen in
            if isOpen, selectedPathPrefix == nil, let first = pathPrefixOptions.first {
                selectedPathPrefix = first
            }
        }
    }

    @ViewBuilder
    private func profileButton(for profile: ChromeProfile, index: Int) -> some View {
        let pick = {
            let effectiveRemember = canRemember && remember
            onChoice(PickerSelection(
                profile: profile,
                remember: effectiveRemember,
                pathPrefix: effectiveRemember ? resolvedPathPrefix : nil
            ))
        }
        let button = Button(action: pick) {
            rowContent(for: profile, index: index)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovered = inside ? profile.id : (hovered == profile.id ? nil : hovered)
        }

        if index == 0 {
            button.keyboardShortcut(.defaultAction)
        } else if index < 9 {
            // Digits 2–9. The default-action profile already responds to "1"
            // via Return; users with multiple profiles can still hit "1" if we
            // assign it explicitly here, but that's redundant.
            button.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        } else {
            button
        }
    }

    private func rowContent(for profile: ChromeProfile, index: Int) -> some View {
        let isHover = hovered == profile.id
        let theme = profile.themeColor
        return HStack(spacing: 12) {
            ProfileAvatar(profile: profile, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.primary)
                if !profile.userName.isEmpty {
                    Text(profile.userName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if index < 9 {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            Image(systemName: "arrow.up.forward")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHover
                      ? theme.opacity(0.18)
                      : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isHover ? theme.opacity(0.7) : Color.primary.opacity(0.08),
                              lineWidth: isHover ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isHover)
    }
}
