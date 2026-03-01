import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Devices View

struct DevicesView: View {
    let accountManager: AccountManager

    @State private var devices: [DeviceSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var deviceToRemove: DeviceSession?
    @State private var isRemoving = false

    private var account: Account? { accountManager.account }

    private var currentDeviceId: String {
        #if os(iOS)
        UIDevice.current.identifierForVendor?.uuidString ?? ""
        #else
        UserDefaults.standard.string(forKey: "doppler_device_id") ?? ""
        #endif
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            GlassEffectContainer {
                VStack(spacing: Design.Spacing.lg) {
                    // Device count header
                    deviceCountHeader

                    // Device list
                    if isLoading {
                        loadingPlaceholder
                    } else if let error = errorMessage {
                        errorView(error)
                    } else if devices.isEmpty {
                        emptyState
                    } else {
                        deviceList
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.md)
            }
        }
        .navigationTitle("Devices")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task {
            await loadDevices()
        }
        .refreshable {
            await loadDevices()
        }
        .confirmationDialog(
            "Remove Device",
            isPresented: Binding(
                get: { deviceToRemove != nil },
                set: { if !$0 { deviceToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let device = deviceToRemove {
                Button("Remove \(device.deviceName)", role: .destructive) {
                    Task { await removeDevice(device) }
                }
                Button("Cancel", role: .cancel) {
                    deviceToRemove = nil
                }
            }
        } message: {
            Text("This device will be signed out and removed from your account.")
        }
    }

    // MARK: - Device Count Header

    @ViewBuilder
    private var deviceCountHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Active Devices")
                    .font(.system(.headline, design: .rounded, weight: .semibold))

                Text("\(devices.count) of \(account?.maxDevices ?? 10)")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Circular progress
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: deviceRatio)
                    .stroke(deviceRatioColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(devices.count)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
            }
            .frame(width: 40, height: 40)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))
    }

    private var deviceRatio: CGFloat {
        let max = CGFloat(account?.maxDevices ?? 10)
        guard max > 0 else { return 0 }
        return min(CGFloat(devices.count) / max, 1.0)
    }

    private var deviceRatioColor: Color {
        let ratio = deviceRatio
        if ratio >= 0.9 { return .red }
        if ratio >= 0.7 { return .orange }
        return Design.Colors.teal
    }

    // MARK: - Device List

    @ViewBuilder
    private var deviceList: some View {
        VStack(spacing: 0) {
            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                deviceRow(device)

                if index < devices.count - 1 {
                    Divider().padding(.leading, 48)
                }
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))
    }

    @ViewBuilder
    private func deviceRow(_ device: DeviceSession) -> some View {
        let isCurrentDevice = device.deviceId == currentDeviceId

        HStack(spacing: 12) {
            // Device type icon
            Image(systemName: device.typeIcon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isCurrentDevice ? Design.Colors.teal : .secondary)
                .frame(width: 28)

            // Device info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(device.deviceName)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .lineLimit(1)

                    if isCurrentDevice {
                        Text("This Device")
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Design.Colors.teal, in: Capsule())
                    }
                }

                HStack(spacing: 4) {
                    Text(device.typeDisplayName)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(device.lastActiveAt, style: .relative)
                        .foregroundStyle(.tertiary)
                }
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Remove button (not for current device)
            if !isCurrentDevice {
                Button {
                    deviceToRemove = device
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .disabled(isRemoving)
            }
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    // MARK: - States

    @ViewBuilder
    private var loadingPlaceholder: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                            .frame(width: 120, height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                            .frame(width: 80, height: 10)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                .redacted(reason: .placeholder)

                if i < 2 { Divider().padding(.leading, 48) }
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: Design.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadDevices() }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Design.Colors.teal)
        }
        .padding(Design.Spacing.xl)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Design.Spacing.md) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No devices found")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(Design.Spacing.xl)
    }

    // MARK: - Actions

    private func loadDevices() async {
        guard let accountId = account?.accountId else {
            errorMessage = "Not logged in."
            isLoading = false
            return
        }

        isLoading = devices.isEmpty
        errorMessage = nil

        do {
            devices = try await DeviceSessionService.fetchDevices(accountId: accountId)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func removeDevice(_ device: DeviceSession) async {
        guard let accountId = account?.accountId else { return }

        isRemoving = true
        defer { isRemoving = false }

        do {
            try await DeviceSessionService.removeDevice(accountId: accountId, deviceId: device.deviceId)
            withAnimation(Design.Animation.springDefault) {
                devices.removeAll { $0.id == device.id }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Previews

#Preview("Devices") {
    NavigationStack {
        DevicesView(accountManager: AccountManager())
    }
}
