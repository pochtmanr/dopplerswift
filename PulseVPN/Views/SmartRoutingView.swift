import SwiftUI

struct SmartRoutingView: View {
    @Binding var isEnabled: Bool
    @Binding var selectedCountryCode: String
    let detectedCountryCode: String?
    let vpnStatus: ConnectionStatus
    @Binding var customDomains: [String]

    @State private var showAddDomain = false
    @State private var newDomainText = ""

    // MARK: - Country Data

    private static let countries: [(code: String, name: String, flag: String)] = [
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
        countries.first(where: { $0.code == code })?.name ?? code
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

    // MARK: - Bypass Rules

    private struct BypassRule: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
    }

    private var bypassRules: [BypassRule] {
        let tld = activeTLD
        return [
            BypassRule(icon: "globe", text: "\(tld) websites"),
            BypassRule(icon: "building.columns.fill", text: "Government & banking services"),
            BypassRule(icon: "play.tv.fill", text: "Local streaming & media"),
            BypassRule(icon: "cart.fill", text: "Domestic e-commerce"),
        ]
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Design.Spacing.lg) {
                heroIcon
                toggleCard
                statusBanner
                countrySelectorCard
                bypassRulesSection
                customDomainsSection
                footer
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.lg)
        }
        .background(Design.Colors.surfaceBackground)
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
            Text("Enter a domain to bypass VPN routing.")
        }
    }

    // MARK: - Hero Icon

    private var heroIcon: some View {
        Image(systemName: "arrow.triangle.branch")
            .font(.system(size: 60))
            .foregroundStyle(isActive ? Design.Colors.connected : Design.Colors.textTertiary)
            .shadow(
                color: isActive ? Design.Colors.connected.opacity(0.4) : .clear,
                radius: isActive ? 16 : 0
            )
            .scaleEffect(isActive ? 1.0 : 0.9)
            .modifier(SmartRoutingPulseModifier(isActive: isActive))
            .animation(Design.Animation.springDefault, value: isActive)
            .padding(.top, Design.Spacing.md)
            .accessibilityLabel(isActive ? "Smart routing active" : "Smart routing inactive")
    }

    // MARK: - Toggle Card

    private var toggleCard: some View {
        HStack(spacing: Design.Spacing.md) {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Text("Smart Routing")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Design.Colors.textPrimary)

                Text("Bypass VPN for domestic sites")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Design.Colors.textSecondary)
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .tint(Design.Colors.connected)
                #if os(iOS)
                .sensoryFeedback(.selection, trigger: isEnabled)
                #endif
        }
        .padding(Design.Spacing.md)
        .background(Design.Colors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                .strokeBorder(Design.Colors.textTertiary.opacity(0.2), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Smart Routing toggle, currently \(isEnabled ? "enabled" : "disabled")")
        .accessibilityHint("Double tap to \(isEnabled ? "disable" : "enable") smart routing")
    }

    // MARK: - Status Banner

    private var statusBanner: some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: statusIcon)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))

            Text(statusText)
                .font(.system(.caption, design: .rounded, weight: .semibold))
        }
        .foregroundStyle(statusForeground)
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(statusBackground.opacity(0.15))
        .clipShape(Capsule())
        .animation(Design.Animation.springDefault, value: isActive)
        .animation(Design.Animation.springDefault, value: isEnabled)
        .accessibilityLabel(statusAccessibilityLabel)
    }

    private var statusIcon: String {
        if isActive {
            return "checkmark.circle.fill"
        } else if isEnabled {
            return "exclamationmark.triangle.fill"
        } else {
            return "minus.circle.fill"
        }
    }

    private var statusText: String {
        if isActive {
            let code = selectedCountryCode
            return "Active \u{2014} Bypassing \(code) traffic"
        } else if isEnabled {
            return "Requires VPN Connection"
        } else {
            return "Disabled"
        }
    }

    private var statusBackground: Color {
        if isActive {
            return Design.Colors.connected
        } else if isEnabled {
            return .orange
        } else {
            return Design.Colors.textTertiary
        }
    }

    private var statusForeground: Color {
        if isActive {
            return Design.Colors.connected
        } else if isEnabled {
            return .orange
        } else {
            return Design.Colors.textSecondary
        }
    }

    private var statusAccessibilityLabel: String {
        if isActive {
            return "Smart routing is active, bypassing \(Self.countryName(for: selectedCountryCode)) traffic"
        } else if isEnabled {
            return "Smart routing is enabled but requires a VPN connection"
        } else {
            return "Smart routing is disabled"
        }
    }

    // MARK: - Country Selector Card

    private var countrySelectorCard: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("Bypass Country")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Design.Colors.textPrimary)

            Menu {
                ForEach(Self.countries, id: \.code) { country in
                    Button {
                        withAnimation(Design.Animation.springQuick) {
                            selectedCountryCode = country.code
                        }
                    } label: {
                        Label {
                            Text("\(country.flag) \(country.name)")
                        } icon: {
                            if selectedCountryCode == country.code {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: Design.Spacing.sm) {
                    Text(Self.flagEmoji(for: selectedCountryCode))
                        .font(.system(size: 28))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.countryName(for: selectedCountryCode))
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(Design.Colors.textPrimary)

                        if isAutoDetected {
                            Text("(auto-detected)")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Design.Colors.accent)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Design.Colors.textTertiary)
                }
                .padding(Design.Spacing.md)
                .background(Design.Colors.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                        .strokeBorder(Design.Colors.textTertiary.opacity(0.2), lineWidth: 0.5)
                )
            }
            .accessibilityLabel("Bypass country: \(Self.countryName(for: selectedCountryCode))\(isAutoDetected ? ", auto-detected" : "")")
            .accessibilityHint("Double tap to change the bypass country")
        }
        .padding(Design.Spacing.md)
        .background(Design.Colors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                .strokeBorder(Design.Colors.textTertiary.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Bypass Rules Section

    private var bypassRulesSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("BYPASS RULES")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Design.Colors.textTertiary)
                .padding(.leading, Design.Spacing.xs)

            VStack(spacing: Design.Spacing.xs) {
                ForEach(bypassRules) { rule in
                    bypassRow(icon: rule.icon, text: rule.text)
                }
            }
        }
    }

    private func bypassRow(icon: String, text: String) -> some View {
        HStack(spacing: Design.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(isActive ? Design.Colors.accent : Design.Colors.textTertiary)
                .frame(width: 24)

            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Design.Colors.textPrimary)

            Spacer()

            Image(systemName: isActive ? "checkmark" : "minus")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(isActive ? Design.Colors.connected : Design.Colors.textTertiary)
                .contentTransition(.symbolEffect(.replace))
        }
        .padding(Design.Spacing.md)
        .background(Design.Colors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
        .opacity(isActive ? 1.0 : 0.5)
        .animation(Design.Animation.springDefault, value: isActive)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text): \(isActive ? "Active" : "Inactive")")
    }

    // MARK: - Custom Domains Section

    private var customDomainsSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("CUSTOM DOMAINS")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Design.Colors.textTertiary)
                .padding(.leading, Design.Spacing.xs)

            if customDomains.isEmpty {
                emptyDomainsPlaceholder
            } else {
                domainsList
            }

            addDomainButton
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

                Text("Add domains you want to always bypass VPN")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Design.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.vertical, Design.Spacing.lg)
        .padding(.horizontal, Design.Spacing.md)
        .background(Design.Colors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                .strokeBorder(Design.Colors.textTertiary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var domainsList: some View {
        VStack(spacing: Design.Spacing.xs) {
            ForEach(Array(customDomains.enumerated()), id: \.offset) { index, domain in
                domainRow(domain: domain, index: index)
            }
        }
    }

    private func domainRow(domain: String, index: Int) -> some View {
        HStack(spacing: Design.Spacing.md) {
            Image(systemName: "globe")
                .font(.body)
                .foregroundStyle(isActive ? Design.Colors.accent : Design.Colors.textTertiary)
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
            .accessibilityHint("Double tap to remove this domain from bypass list")
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .background(Design.Colors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        ))
    }

    private var addDomainButton: some View {
        Button {
            showAddDomain = true
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.body)

                Text("Add Domain")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
            }
            .foregroundStyle(Design.Colors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.md)
            .background(Design.Colors.accent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(Design.Colors.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add custom domain")
        .accessibilityHint("Double tap to add a domain to the bypass list")
    }

    // MARK: - Footer

    private var footer: some View {
        Text("Powered by Xray geosite/geoip routing")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Design.Colors.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, Design.Spacing.sm)
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
            customDomains: .constant(["sparkasse.de", "commerzbank.de"])
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
            customDomains: .constant(["mybank.de"])
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
            customDomains: .constant([])
        )
    }
}
