import SwiftUI

// MARK: - Speed Test Widget

struct SpeedTestWidget: View {
    let compact: Bool
    @Binding var result: SpeedTestResult?
    @Binding var isRunning: Bool

    @State private var phase: SpeedTestPhase = .idle

    private var hasResult: Bool { result != nil }

    // MARK: - Body

    var body: some View {
        Button {
            guard !isRunning else { return }
            runTest()
        } label: {
            Group {
                if compact {
                    compactLayout
                } else {
                    expandedLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(
                isRunning ? .regular.tint(Design.Colors.teal.opacity(0.1)) : .regular,
                in: .rect(cornerRadius: Design.CornerRadius.lg)
            )
        }
        .buttonStyle(ConnectButtonStyle())
        .disabled(isRunning)
        .accessibilityLabel("Speed Test")
        .accessibilityHint(isRunning ? "Test in progress" : "Double tap to run speed test")
    }

    // MARK: - Compact Layout (square widget)

    @ViewBuilder
    private var compactLayout: some View {
        VStack(spacing: Design.Spacing.sm) {
            if isRunning {
                ProgressView()
                    .controlSize(.regular)
                    .tint(Design.Colors.teal)

                Text(phaseLabel)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(Design.Colors.teal)
            } else if let result {
                resultDisplay(result)
            } else {
                idleDisplay
            }
        }
    }

    // MARK: - Expanded Layout (horizontal bar)

    @ViewBuilder
    private var expandedLayout: some View {
        HStack(spacing: Design.Spacing.md) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
                    .tint(Design.Colors.teal)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Speed Test")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text(phaseLabel)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Design.Colors.teal)
                }

                Spacer()
            } else if let result {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Design.Colors.teal)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Speed Test")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Design.Colors.textPrimary)

                    HStack(spacing: Design.Spacing.sm) {
                        Label(String(format: "%.1f", result.downloadMbps), systemImage: "arrow.down")
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .foregroundStyle(Design.Colors.connected)

                        Label(String(format: "%.1f", result.uploadMbps), systemImage: "arrow.up")
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .foregroundStyle(Design.Colors.teal)

                        Text("\(result.pingMs) ms")
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .foregroundStyle(Design.Colors.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Design.Colors.teal, in: Circle())
            } else {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Design.Colors.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Speed Test")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text("Tap to measure")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Design.Colors.textSecondary)
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Design.Colors.teal, in: Circle())
            }
        }
        .padding(.horizontal, Design.Spacing.md)
    }

    // MARK: - Compact Sub-Views

    @ViewBuilder
    private var idleDisplay: some View {
        Image(systemName: "gauge.with.dots.needle.33percent")
            .font(.system(size: 28, weight: .medium))
            .foregroundStyle(Design.Colors.textTertiary)

        Text("Speed Test")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(Design.Colors.textPrimary)

        Text("Tap to test")
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .foregroundStyle(Design.Colors.textSecondary)
    }

    @ViewBuilder
    private func resultDisplay(_ result: SpeedTestResult) -> some View {
        Image(systemName: "gauge.with.dots.needle.67percent")
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(Design.Colors.teal)

        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Design.Colors.connected)

                Text(String(format: "%.0f", result.downloadMbps))
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 4) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Design.Colors.teal)

                Text(String(format: "%.0f", result.uploadMbps))
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .contentTransition(.numericText())
            }
        }

        Text("Mbps")
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .foregroundStyle(Design.Colors.textTertiary)
    }

    // MARK: - Phase Label

    private var phaseLabel: String {
        switch phase {
        case .idle: "Ready"
        case .ping: "Pinging..."
        case .download: "Downloading..."
        case .upload: "Uploading..."
        case .complete: "Done"
        }
    }

    // MARK: - Run Test

    private func runTest() {
        isRunning = true
        Task {
            do {
                let testResult = try await SpeedTestService.run { newPhase in
                    withAnimation(Design.Animation.springQuick) {
                        phase = newPhase
                    }
                }
                withAnimation(Design.Animation.springDefault) {
                    result = testResult
                    isRunning = false
                    phase = .idle
                }
            } catch {
                NSLog("[SpeedTest] Failed: %@", error.localizedDescription)
                withAnimation(Design.Animation.springDefault) {
                    isRunning = false
                    phase = .idle
                }
            }
        }
    }
}
