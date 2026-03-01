import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct SmartRoutingView: View {
    @Binding var isEnabled: Bool
    @Binding var selectedCountryCode: String
    let detectedCountryCode: String?
    let vpnStatus: ConnectionStatus
    @Binding var customDomains: [String]

    // Bypass category toggles
    @Binding var bypassTLDWebsites: Bool
    @Binding var bypassGovernmentBanking: Bool

    @State private var showAddDomain = false
    @State private var newDomainText = ""

    // Favicon cache: key absent = loading, .some(image) = success, .some(nil) = failed
    #if os(iOS)
    @State private var favicons: [String: UIImage?] = [:]
    #else
    @State private var favicons: [String: NSImage?] = [:]
    #endif

    // Paste error feedback
    @State private var pasteErrorMessage: String?

    // MARK: - Country Data

    // Must match countries in stripped geoip.dat (scripts/strip-geoip.py)
    private static let countries: [(code: String, name: LocalizedStringResource, flag: String)] = [
        ("DE", "Germany", "\u{1F1E9}\u{1F1EA}"),
        ("GB", "United Kingdom", "\u{1F1EC}\u{1F1E7}"),
        ("FR", "France", "\u{1F1EB}\u{1F1F7}"),
        ("NL", "Netherlands", "\u{1F1F3}\u{1F1F1}"),
        ("RU", "Russia", "\u{1F1F7}\u{1F1FA}"),
        ("US", "United States", "\u{1F1FA}\u{1F1F8}"),
        ("TR", "Turkey", "\u{1F1F9}\u{1F1F7}"),
        ("IT", "Italy", "\u{1F1EE}\u{1F1F9}"),
        ("ES", "Spain", "\u{1F1EA}\u{1F1F8}"),
        ("PL", "Poland", "\u{1F1F5}\u{1F1F1}"),
        ("UA", "Ukraine", "\u{1F1FA}\u{1F1E6}"),
        ("KZ", "Kazakhstan", "\u{1F1F0}\u{1F1FF}"),
        ("AE", "UAE", "\u{1F1E6}\u{1F1EA}"),
        ("IL", "Israel", "\u{1F1EE}\u{1F1F1}"),
        ("CN", "China", "\u{1F1E8}\u{1F1F3}"),
        ("BR", "Brazil", "\u{1F1E7}\u{1F1F7}"),
        ("JP", "Japan", "\u{1F1EF}\u{1F1F5}"),
        ("KR", "South Korea", "\u{1F1F0}\u{1F1F7}"),
        ("IN", "India", "\u{1F1EE}\u{1F1F3}"),
        ("AU", "Australia", "\u{1F1E6}\u{1F1FA}"),
        ("CA", "Canada", "\u{1F1E8}\u{1F1E6}"),
    ]

    // MARK: - Helpers

    private static func flagEmoji(for code: String) -> String {
        countries.first(where: { $0.code == code })?.flag ?? "\u{1F3F3}\u{FE0F}"
    }

    private static func countryName(for code: String) -> String {
        guard let resource = countries.first(where: { $0.code == code })?.name else { return code }
        return String(localized: resource)
    }

    // MARK: - Computed State

    private var isActive: Bool {
        isEnabled && vpnStatus == .connected
    }

    private var isAutoDetected: Bool {
        if let detected = detectedCountryCode {
            return selectedCountryCode == detected
        }
        return false
    }

    private var activeTLD: String {
        ".\(selectedCountryCode.lowercased())"
    }

    private var togglesDisabled: Bool {
        !isEnabled || vpnStatus != .connected
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            GlassEffectContainer {
                VStack(spacing: Design.Spacing.lg) {
                    warningBanner
                    smartRoutingCard
                    bypassRulesSection
                    customDomainsSection
                    footer
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.lg)
            }
        }
        .onAppear { fetchMissingFavicons() }
        .onChange(of: customDomains) { _, _ in fetchMissingFavicons() }
        .alert("Add Custom Domain", isPresented: $showAddDomain) {
            TextField("e.g., mybank.de", text: $newDomainText)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            Button("Add") {
                addDomain()
            }
            Button("Cancel", role: .cancel) {
                newDomainText = ""
            }
        } message: {
            Text("Enter a domain to route directly.")
        }
    }

    // MARK: - Warning Banner (top, only when enabled but VPN disconnected)

    @ViewBuilder
    private var warningBanner: some View {
        if isEnabled && vpnStatus != .connected {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold))

                Text("Requires VPN Connection")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(.orange.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(Design.Animation.springDefault, value: vpnStatus)
        }
    }

    // MARK: - Unified Smart Routing Card

    private var smartRoutingCard: some View {
        HStack(spacing: Design.Spacing.md) {
            // Left: animated icon
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(isActive ? Design.Colors.teal : Design.Colors.textTertiary)
                .shadow(
                    color: isActive ? Design.Colors.teal.opacity(0.4) : .clear,
                    radius: isActive ? 10 : 0
                )
                .modifier(SmartRoutingPulseModifier(isActive: isActive))
                .animation(Design.Animation.springDefault, value: isActive)
                .frame(width: 44)

            // Middle: title + country picker
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Text("Smart Routing")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Design.Colors.textPrimary)

                countryPickerButton
            }

            Spacer()

            // Right: toggle
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .tint(Design.Colors.teal)
                #if os(iOS)
                .sensoryFeedback(.selection, trigger: isEnabled)
                #endif
        }
        .padding(Design.Spacing.md)
        .glassEffect(
            isActive ? .regular.tint(Design.Colors.teal.opacity(0.15)) : .regular,
            in: .rect(cornerRadius: Design.CornerRadius.lg)
        )
        .animation(Design.Animation.springDefault, value: isActive)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Smart Routing toggle, currently \(isEnabled ? "enabled" : "disabled"), country: \(Self.countryName(for: selectedCountryCode))")
    }

    private var countryPickerButton: some View {
        Menu {
            ForEach(Self.countries, id: \.code) { country in
                Button {
                    withAnimation(Design.Animation.springQuick) {
                        selectedCountryCode = country.code
                    }
                } label: {
                    Label {
                        Text("\(country.flag) \(String(localized: country.name))")
                    } icon: {
                        if selectedCountryCode == country.code {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: Design.Spacing.xs) {
                Text(Self.flagEmoji(for: selectedCountryCode))
                    .font(.system(size: 16))

                Text(Self.countryName(for: selectedCountryCode))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Design.Colors.textSecondary)

                if isAutoDetected {
                    Text("(auto)")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Design.Colors.teal)
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Design.Colors.textTertiary)
            }
        }
        .accessibilityLabel("Smart Route country: \(Self.countryName(for: selectedCountryCode))")
        .accessibilityHint("Double tap to change the Smart Route country")
    }

    // MARK: - Bypass Rules Section (with toggles)

    private var bypassRulesSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("DIRECT ROUTING RULES")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Design.Colors.textTertiary)
                .padding(.leading, Design.Spacing.xs)

            VStack(spacing: 0) {
                bypassToggleRow(
                    icon: "globe",
                    text: String(localized: "\(activeTLD) websites"),
                    isOn: $bypassTLDWebsites
                )
                Divider().padding(.leading, 40)
                bypassToggleRow(
                    icon: "building.columns.fill",
                    text: String(localized: "Government & banking"),
                    isOn: $bypassGovernmentBanking
                )
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.xs)
            .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))
            .opacity(togglesDisabled ? 0.5 : 1.0)
            .animation(Design.Animation.springDefault, value: isActive)
        }
    }

    private func bypassToggleRow(icon: String, text: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: Design.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(isActive && isOn.wrappedValue ? Design.Colors.teal : Design.Colors.textTertiary)
                .frame(width: 24)

            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Design.Colors.textPrimary)

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Design.Colors.teal)
                .disabled(togglesDisabled)
        }
        .padding(.vertical, 14)
        .animation(Design.Animation.springDefault, value: isOn.wrappedValue)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text): \(isOn.wrappedValue ? "Enabled" : "Disabled")")
    }

    // MARK: - Custom Domains Section

    private var customDomainsSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("CUSTOM DOMAINS")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Design.Colors.textTertiary)
                .padding(.leading, Design.Spacing.xs)

            VStack(spacing: 0) {
                if customDomains.isEmpty {
                    emptyDomainsPlaceholder
                } else {
                    domainsList
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.xs)
            .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))

            addDomainButton
            learnMoreLink
        }
    }

    private var emptyDomainsPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: Design.Spacing.sm) {
                Image(systemName: "globe.badge.chevron.backward")
                    .font(.title2)
                    .foregroundStyle(Design.Colors.textTertiary)

                Text("No custom domains")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Design.Colors.textSecondary)

                Text("Add domains you want to always route directly")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Design.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.vertical, Design.Spacing.lg)
    }

    private var domainsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(customDomains.enumerated()), id: \.offset) { index, domain in
                if index > 0 {
                    Divider().padding(.leading, 40)
                }
                domainRow(domain: domain, index: index)
            }
        }
    }

    private func domainRow(domain: String, index: Int) -> some View {
        HStack(spacing: Design.Spacing.md) {
            faviconView(for: domain)
                .frame(width: 24)

            Text(domain)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(Design.Colors.textPrimary)

            Spacer()

            Button {
                withAnimation(Design.Animation.springQuick) {
                    _ = customDomains.remove(at: index)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(.red.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(domain)")
            .accessibilityHint("Double tap to remove this domain from direct routing list")
        }
        .padding(.vertical, Design.Spacing.sm)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        ))
    }

    private var addDomainButton: some View {
        VStack(spacing: Design.Spacing.xs) {
            Button {
                showAddDomain = true
            } label: {
                HStack(spacing: Design.Spacing.sm) {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)

                    Text("Add Domain")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                }
                .foregroundStyle(Design.Colors.teal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.md)
                .background(Design.Colors.teal.opacity(0.1))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Design.Colors.teal.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add custom domain")
            .accessibilityHint("Double tap to add a domain to the direct routing list")

            #if os(iOS)
            Button {
                pasteFromClipboard()
            } label: {
                HStack(spacing: Design.Spacing.sm) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.body)

                    Text("Paste from Clipboard")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.md)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .opacity(UIPasteboard.general.hasStrings ? 1.0 : 0.4)
            .disabled(!UIPasteboard.general.hasStrings)
            .accessibilityLabel("Paste domain from clipboard")
            .accessibilityHint("Double tap to paste a domain from your clipboard")

            if let errorMessage = pasteErrorMessage {
                Text(errorMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            #endif
        }
    }

    @ViewBuilder
    private var learnMoreLink: some View {
        NavigationLink {
            HelpSupportView()
        } label: {
            HStack(spacing: Design.Spacing.xs) {
                Text("Learn how Smart Route works")
                    .font(.system(.caption, design: .rounded))

                Image(systemName: "chevron.forward")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Design.Colors.teal)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, Design.Spacing.xs)
    }

    // MARK: - Footer

    private var footer: some View {
        Text("Powered by advanced geo-based routing")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Design.Colors.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, Design.Spacing.sm)
    }

    // MARK: - Favicon

    @ViewBuilder
    private func faviconView(for domain: String) -> some View {
        if let cached = favicons[domain] {
            if let image = cached {
                #if os(iOS)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                #else
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                #endif
            } else {
                Image(systemName: "globe")
                    .font(.body)
                    .foregroundStyle(isActive ? Design.Colors.teal : Design.Colors.textTertiary)
            }
        } else {
            ProgressView()
                .frame(width: 20, height: 20)
        }
    }

    private func fetchMissingFavicons() {
        for domain in customDomains where favicons[domain] == nil {
            Task { await fetchFavicon(for: domain) }
        }
    }

    private func fetchFavicon(for domain: String) async {
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=64") else {
            favicons[domain] = .some(nil)
            return
        }
        do {
            let request = URLRequest(url: url, timeoutInterval: 5)
            let (data, _) = try await URLSession.shared.data(for: request)
            #if os(iOS)
            if let image = UIImage(data: data), image.size.width > 1 {
                favicons[domain] = image
            } else {
                favicons[domain] = .some(nil)
            }
            #else
            if let image = NSImage(data: data), image.size.width > 1 {
                favicons[domain] = image
            } else {
                favicons[domain] = .some(nil)
            }
            #endif
        } catch {
            favicons[domain] = .some(nil)
        }
    }

    // MARK: - Actions

    private func addDomain() {
        let trimmed = newDomainText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !trimmed.isEmpty, !customDomains.contains(trimmed) else {
            newDomainText = ""
            return
        }

        withAnimation(Design.Animation.springQuick) {
            customDomains.append(trimmed)
        }
        newDomainText = ""
    }

    #if os(iOS)
    private func pasteFromClipboard() {
        guard let raw = UIPasteboard.general.string else {
            showPasteError(String(localized: "Nothing to paste"))
            return
        }

        let domain = extractDomain(from: raw)

        guard !domain.isEmpty, isValidDomain(domain) else {
            showPasteError(String(localized: "No valid domain found"))
            return
        }

        guard !customDomains.contains(domain) else {
            showPasteError(String(localized: "Domain already added"))
            return
        }

        withAnimation(Design.Animation.springQuick) {
            customDomains.append(domain)
        }
    }

    private func extractDomain(from raw: String) -> String {
        let firstLine = raw.components(separatedBy: .newlines).first ?? raw
        var trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Strip protocol and extract host if it's a URL
        if trimmed.contains("://") {
            if let url = URL(string: trimmed), let host = url.host {
                trimmed = host
            } else {
                // Manual strip if URL parsing fails
                if let range = trimmed.range(of: "://") {
                    trimmed = String(trimmed[range.upperBound...])
                }
                // Remove path
                if let slashIndex = trimmed.firstIndex(of: "/") {
                    trimmed = String(trimmed[..<slashIndex])
                }
            }
        }

        // Strip www. prefix
        if trimmed.hasPrefix("www.") {
            trimmed = String(trimmed.dropFirst(4))
        }

        // Strip trailing dot
        while trimmed.hasSuffix(".") {
            trimmed = String(trimmed.dropLast())
        }

        return trimmed
    }

    private func isValidDomain(_ domain: String) -> Bool {
        guard !domain.isEmpty, domain.contains("."), !domain.contains(" ") else {
            return false
        }
        // Reject IP addresses
        let parts = domain.split(separator: ".")
        let allNumeric = parts.allSatisfy { $0.allSatisfy(\.isNumber) }
        if allNumeric { return false }

        // Basic domain character validation
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
        return domain.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func showPasteError(_ message: String) {
        withAnimation(Design.Animation.springQuick) {
            pasteErrorMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(Design.Animation.springQuick) {
                pasteErrorMessage = nil
            }
        }
    }
    #endif
}

// MARK: - Pulse Animation Modifier

private struct SmartRoutingPulseModifier: ViewModifier {
    let isActive: Bool

    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive && isPulsing ? 1.05 : 1.0)
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    startPulsing()
                } else {
                    isPulsing = false
                }
            }
            .onAppear {
                if isActive {
                    startPulsing()
                }
            }
    }

    private func startPulsing() {
        withAnimation(
            .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
        ) {
            isPulsing = true
        }
    }
}

// MARK: - Previews

#Preview("Active") {
    NavigationStack {
        SmartRoutingView(
            isEnabled: .constant(true),
            selectedCountryCode: .constant("DE"),
            detectedCountryCode: "DE",
            vpnStatus: .connected,
            customDomains: .constant(["sparkasse.de", "commerzbank.de"]),
            bypassTLDWebsites: .constant(true),
            bypassGovernmentBanking: .constant(true)
        )
    }
}

#Preview("Enabled - VPN Off") {
    NavigationStack {
        SmartRoutingView(
            isEnabled: .constant(true),
            selectedCountryCode: .constant("DE"),
            detectedCountryCode: "DE",
            vpnStatus: .disconnected,
            customDomains: .constant(["mybank.de"]),
            bypassTLDWebsites: .constant(true),
            bypassGovernmentBanking: .constant(true)
        )
    }
}

#Preview("Disabled") {
    NavigationStack {
        SmartRoutingView(
            isEnabled: .constant(false),
            selectedCountryCode: .constant("GB"),
            detectedCountryCode: nil,
            vpnStatus: .disconnected,
            customDomains: .constant([]),
            bypassTLDWebsites: .constant(true),
            bypassGovernmentBanking: .constant(true)
        )
    }
}
