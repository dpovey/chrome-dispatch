import SwiftUI
import AppKit

struct MappingsView: View {
    let profiles: [ChromeProfile]

    @State private var entries: [Entry] = []
    @State private var status: String = ""
    @State private var isDefaultBrowser: Bool = false
    @State private var filter: String = ""
    @State private var sortOrder: SortOrder = .hostAscending
    @State private var showingAdd: Bool = false

    enum SortOrder: String, CaseIterable, Identifiable {
        case hostAscending = "Host (A→Z)"
        case hostDescending = "Host (Z→A)"
        case profileAscending = "Profile (A→Z)"
        case profileDescending = "Profile (Z→A)"
        var id: String { rawValue }
    }

    struct Entry: Identifiable, Hashable {
        let id = UUID()
        var host: String
        var pathPrefix: String?
        var profile: String
        var userName: String?

        var displayKey: String {
            if let p = pathPrefix, !p.isEmpty { return host + p }
            return host
        }
    }

    private var visibleEntries: [Entry] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = needle.isEmpty
            ? entries
            : entries.filter {
                $0.displayKey.lowercased().contains(needle)
                    || profileName(for: $0.profile).lowercased().contains(needle)
            }
        return filtered.sorted(by: sortComparator)
    }

    private func sortComparator(_ a: Entry, _ b: Entry) -> Bool {
        switch sortOrder {
        case .hostAscending:
            return a.displayKey.localizedCaseInsensitiveCompare(b.displayKey) == .orderedAscending
        case .hostDescending:
            return a.displayKey.localizedCaseInsensitiveCompare(b.displayKey) == .orderedDescending
        case .profileAscending:
            let pa = profileName(for: a.profile), pb = profileName(for: b.profile)
            if pa == pb { return a.displayKey.localizedCaseInsensitiveCompare(b.displayKey) == .orderedAscending }
            return pa.localizedCaseInsensitiveCompare(pb) == .orderedAscending
        case .profileDescending:
            let pa = profileName(for: a.profile), pb = profileName(for: b.profile)
            if pa == pb { return a.displayKey.localizedCaseInsensitiveCompare(b.displayKey) == .orderedAscending }
            return pa.localizedCaseInsensitiveCompare(pb) == .orderedDescending
        }
    }

    private func profileName(for dir: String) -> String {
        profiles.first(where: { $0.directory == dir })?.name ?? dir
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chrome Dispatch")
                        .font(.title2.weight(.semibold))
                    Text("Pick a Chrome profile per site, automatically.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(isDefaultBrowser ? "Default Browser ✓" : "Set as Default Browser") {
                    Task { await setAsDefaultBrowser() }
                }
                .disabled(isDefaultBrowser)
            }

            Divider()

            HStack(spacing: 10) {
                Text("Saved sites").font(.headline)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Filter", text: $filter)
                        .textFieldStyle(.plain)
                        .frame(minWidth: 120, maxWidth: 200)
                    if !filter.isEmpty {
                        Button {
                            filter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.1))
                )
                Picker("", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { o in
                        Text(o.rawValue).tag(o)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add mapping")
                Button {
                    exportMappings()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export mappings to a file")
                .disabled(entries.isEmpty)
                Button {
                    importMappings()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Import mappings from a file (merges with existing)")
            }

            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No mappings yet")
                        .font(.headline)
                    Text("Open a link with Chrome Dispatch — or click + to add one manually.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 24)
            } else if visibleEntries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No matches for \"\(filter)\"")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 24)
            } else {
                List {
                    ForEach(visibleEntries) { entry in
                        HStack(spacing: 10) {
                            if let p = profiles.first(where: { $0.directory == entry.profile }) {
                                ProfileColorDot(profile: p)
                            } else {
                                Circle().fill(Color.secondary.opacity(0.3))
                                    .frame(width: 12, height: 12)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.host)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let p = entry.pathPrefix, !p.isEmpty {
                                    Text(p)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(entry.displayKey)
                            Picker("", selection: bindingForProfile(of: entry)) {
                                ForEach(profiles) { p in
                                    Text(p.name).tag(p.directory)
                                }
                            }
                            .frame(width: 200)
                            .labelsHidden()
                            Button {
                                if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                                    entries.remove(at: idx)
                                    persist()
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove mapping")
                        }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 160)
            }

            HStack {
                Text(footerCountText)
                    .font(.caption).foregroundStyle(.secondary)
                if !status.isEmpty {
                    Text("•").font(.caption).foregroundStyle(.secondary)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Profiles: " + profiles.map(\.name).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(minWidth: 580, minHeight: 380)
        .onAppear {
            reload()
            checkDefaultBrowser()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Default browser may have been changed externally (System Settings).
            checkDefaultBrowser()
        }
        .sheet(isPresented: $showingAdd) {
            AddMappingSheet(
                profiles: profiles,
                existingKeys: Set(entries.map(\.displayKey))
            ) { host, pathPrefix, profile in
                let normalizedHost = Mappings.normalize(host)
                let normalizedPath = Mappings.normalizePathPrefix(pathPrefix)
                let email = profiles.first(where: { $0.directory == profile })?.userName
                let userName = (email?.isEmpty ?? true) ? nil : email
                if let idx = entries.firstIndex(where: { $0.host == normalizedHost && $0.pathPrefix == normalizedPath }) {
                    entries[idx].profile = profile
                    entries[idx].userName = userName
                } else {
                    entries.append(Entry(host: normalizedHost, pathPrefix: normalizedPath, profile: profile, userName: userName))
                }
                persist()
                showingAdd = false
            } onCancel: {
                showingAdd = false
            }
        }
    }

    private var footerCountText: String {
        if filter.isEmpty {
            return "\(entries.count) entr\(entries.count == 1 ? "y" : "ies")"
        }
        return "\(visibleEntries.count) of \(entries.count) shown"
    }

    private func bindingForProfile(of entry: Entry) -> Binding<String> {
        Binding(
            get: {
                entries.first(where: { $0.id == entry.id })?.profile ?? entry.profile
            },
            set: { newValue in
                if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                    entries[idx].profile = newValue
                    // Keep the cross-device email in sync with the chosen profile;
                    // empty for unsigned profiles.
                    let email = profiles.first(where: { $0.directory == newValue })?.userName
                    entries[idx].userName = (email?.isEmpty ?? true) ? nil : email
                    persist()
                }
            }
        )
    }

    private func reload() {
        var m = Mappings.load()
        // Legacy installs only stored directory names; backfill emails from the
        // current machine so the next export carries portable identifiers.
        if m.backfillUserNames(profiles: profiles) {
            _ = m.save()
        }
        entries = m.rules
            .map { Entry(host: $0.host, pathPrefix: $0.pathPrefix, profile: $0.profile, userName: $0.userName) }
            .sorted { $0.displayKey < $1.displayKey }
    }

    private func persist() {
        var m = Mappings()
        m.rules = entries.map {
            MappingRule(host: $0.host, pathPrefix: $0.pathPrefix, profile: $0.profile, userName: $0.userName)
        }
        if !m.save() {
            status = "Couldn't save mappings — see Console for details."
        } else if status.hasPrefix("Couldn't save") {
            status = ""
        }
    }

    private func exportMappings() {
        let panel = NSSavePanel()
        panel.title = "Export Chrome Dispatch Mappings"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "chrome-dispatch-mappings.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        var m = Mappings()
        m.rules = entries.map {
            MappingRule(host: $0.host, pathPrefix: $0.pathPrefix, profile: $0.profile, userName: $0.userName)
        }
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(m).write(to: dest, options: .atomic)
            status = "Exported \(entries.count) mapping\(entries.count == 1 ? "" : "s")."
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importMappings() {
        let panel = NSOpenPanel()
        panel.title = "Import Chrome Dispatch Mappings"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let src = panel.url else { return }
        do {
            let data = try Data(contentsOf: src)
            let imported = try JSONDecoder().decode(Mappings.self, from: data)
            var current = Mappings()
            current.rules = entries.map {
                MappingRule(host: $0.host, pathPrefix: $0.pathPrefix, profile: $0.profile, userName: $0.userName)
            }
            // Imported rules with the same host+pathPrefix overwrite local ones;
            // others are appended. Profile resolution happens at lookup time, so
            // imports for accounts not signed in here will fall through to the
            // picker until the user adopts a local profile for them.
            var added = 0, updated = 0
            for r in imported.rules {
                if let idx = current.rules.firstIndex(where: { $0.host == r.host && $0.pathPrefix == r.pathPrefix }) {
                    current.rules[idx] = r
                    updated += 1
                } else {
                    current.rules.append(r)
                    added += 1
                }
            }
            if !current.save() {
                status = "Couldn't save imported mappings — see Console for details."
                return
            }
            reload()
            status = "Imported: \(added) new, \(updated) updated."
        } catch {
            status = "Import failed: \(error.localizedDescription)"
        }
    }

    private func checkDefaultBrowser() {
        let probe = URL(string: "https://example.com")!
        let handler = NSWorkspace.shared.urlForApplication(toOpen: probe)
        isDefaultBrowser = handler?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    private func setAsDefaultBrowser() async {
        let appURL = Bundle.main.bundleURL
        await MainActor.run { status = "Asking macOS to set Chrome Dispatch as default…" }
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http")
            try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https")
            await MainActor.run {
                status = "Set as default browser."
                checkDefaultBrowser()
            }
        } catch {
            await MainActor.run {
                status = "Couldn't set handler: \(error.localizedDescription)"
                checkDefaultBrowser()
            }
        }
    }
}

struct AddMappingSheet: View {
    let profiles: [ChromeProfile]
    let existingKeys: Set<String>
    let onSave: (String, String?, String) -> Void
    let onCancel: () -> Void

    @State private var host: String = ""
    @State private var pathPrefix: String = ""
    @State private var advancedExpanded: Bool = false
    @State private var selectedProfile: String

    init(profiles: [ChromeProfile],
         existingKeys: Set<String>,
         onSave: @escaping (String, String?, String) -> Void,
         onCancel: @escaping () -> Void) {
        self.profiles = profiles
        self.existingKeys = existingKeys
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedProfile = State(initialValue: profiles.first?.directory ?? "Default")
    }

    private var normalizedHost: String { Mappings.normalize(host) }
    private var normalizedPath: String? { Mappings.normalizePathPrefix(pathPrefix) }

    private var displayKey: String {
        if let p = normalizedPath { return normalizedHost + p }
        return normalizedHost
    }

    private var hostInvalid: Bool {
        normalizedHost.isEmpty || normalizedHost.contains("/") || normalizedHost.contains(" ")
    }

    private var validation: String? {
        if normalizedHost.isEmpty { return nil }
        if normalizedHost.contains("/") || normalizedHost.contains(" ") {
            return "Enter just a hostname (e.g. example.com). Use Advanced for a path prefix."
        }
        if existingKeys.contains(displayKey) {
            return "Already mapped — saving will overwrite the existing profile."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add mapping").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Host").font(.caption).foregroundStyle(.secondary)
                TextField("example.com", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submitIfValid)
            }

            DisclosureGroup(isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(normalizedHost.isEmpty ? "host" : normalizedHost)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                        TextField("/path-prefix", text: $pathPrefix)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(submitIfValid)
                    }
                    Text("Match only URLs whose path starts with this prefix. Leave blank to match all paths.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
            } label: {
                Text("Advanced").font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Profile").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $selectedProfile) {
                    ForEach(profiles) { p in
                        Text(p.name).tag(p.directory)
                    }
                }
                .labelsHidden()
            }

            if let v = validation {
                Text(v)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: submitIfValid)
                    .keyboardShortcut(.defaultAction)
                    .disabled(hostInvalid)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func submitIfValid() {
        guard !hostInvalid else { return }
        onSave(normalizedHost, pathPrefix, selectedProfile)
    }
}
