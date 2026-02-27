import SwiftUI

// MARK: - Connection Status View

struct ConnectionStatusView: View {
    let status: ConnectionStatus

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.5
    @State private var ringRotation: Double = 0
    @State private var glowOpacity: Double = 0.3
    @State private var shakeOffset: CGFloat = 0

    private var statusColor: Color {
        Design.Colors.statusColor(for: status)
    }

    private var ringDiameter: CGFloat {
        Design.Size.connectRingDiameter
    }

    var body: some View {
        ZStack {
            ambientGlow

            ringTrack

            switch status {
            case .disconnected:
                idleRing
            case .connecting, .disconnecting:
                spinningRing
                pulsingOuterRing
            case .connected:
                connectedRing
                connectedGlowRing
            case .failed:
                failedRing
            }
        }
        .offset(x: shakeOffset)
        .animation(Design.Animation.springDefault, value: status)
        .onChange(of: status) { oldValue, newValue in
            handleStatusChange(from: oldValue, to: newValue)
        }
        .onAppear {
            if status == .connecting || status == .disconnecting {
                startSpinAnimation()
            }
            if status == .disconnected {
                startIdleAnimation()
            }
            if status == .connected {
                startConnectedAnimation()
            }
        }
    }

    // MARK: - Ambient Glow

    @ViewBuilder
    private var ambientGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        statusColor.opacity(glowOpacity),
                        statusColor.opacity(glowOpacity * 0.3),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: Design.Size.connectButtonDiameter * 0.3,
                    endRadius: ringDiameter * 0.75
                )
            )
            .frame(width: ringDiameter + 60, height: ringDiameter + 60)
    }

    // MARK: - Ring Track

    @ViewBuilder
    private var ringTrack: some View {
        Circle()
            .stroke(statusColor.opacity(0.12), lineWidth: 4)
            .frame(width: ringDiameter, height: ringDiameter)
    }

    // MARK: - Idle Ring (Disconnected)

    @ViewBuilder
    private var idleRing: some View {
        Circle()
            .stroke(statusColor.opacity(0.35), lineWidth: 4)
            .frame(width: ringDiameter, height: ringDiameter)
            .scaleEffect(pulseScale)
            .opacity(pulseOpacity)
    }

    // MARK: - Spinning Ring (Connecting / Disconnecting)

    @ViewBuilder
    private var spinningRing: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(
                AngularGradient(
                    colors: [statusColor.opacity(0), statusColor],
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(100)
                ),
                style: StrokeStyle(lineWidth: 4, lineCap: .round)
            )
            .frame(width: ringDiameter, height: ringDiameter)
            .rotationEffect(.degrees(ringRotation))
    }

    @ViewBuilder
    private var pulsingOuterRing: some View {
        Circle()
            .stroke(statusColor.opacity(0.2), lineWidth: 2)
            .frame(width: ringDiameter + 30, height: ringDiameter + 30)
            .scaleEffect(pulseScale)
            .opacity(pulseOpacity)
    }

    // MARK: - Connected Ring

    @ViewBuilder
    private var connectedRing: some View {
        Circle()
            .stroke(statusColor, lineWidth: 4)
            .frame(width: ringDiameter, height: ringDiameter)
    }

    @ViewBuilder
    private var connectedGlowRing: some View {
        Circle()
            .stroke(statusColor.opacity(0.3), lineWidth: 8)
            .frame(width: ringDiameter, height: ringDiameter)
            .blur(radius: 6)
            .opacity(glowOpacity)
    }

    // MARK: - Failed Ring

    @ViewBuilder
    private var failedRing: some View {
        Circle()
            .stroke(statusColor, lineWidth: 4)
            .frame(width: ringDiameter, height: ringDiameter)
    }

    // MARK: - Animation Control

    private func handleStatusChange(from oldValue: ConnectionStatus, to newValue: ConnectionStatus) {
        stopAllAnimations()

        switch newValue {
        case .disconnected:
            startIdleAnimation()
        case .connecting, .disconnecting:
            startSpinAnimation()
        case .connected:
            startConnectedAnimation()
        case .failed:
            triggerShake()
        }
    }

    private func stopAllAnimations() {
        withAnimation(Design.Animation.springQuick) {
            pulseScale = 1.0
            pulseOpacity = 0.5
            glowOpacity = 0.3
        }
        ringRotation = 0
    }

    private func startIdleAnimation() {
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.04
            pulseOpacity = 0.7
            glowOpacity = 0.15
        }
    }

    private func startSpinAnimation() {
        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.12
            pulseOpacity = 0.15
            glowOpacity = 0.4
        }
    }

    private func startConnectedAnimation() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            glowOpacity = 0.6
        }
    }

    private func triggerShake() {
        withAnimation(.spring(response: 0.1, dampingFraction: 0.2)) {
            shakeOffset = 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.1, dampingFraction: 0.2)) {
                shakeOffset = -8
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
                shakeOffset = 0
            }
        }
    }
}

// MARK: - Previews

#Preview("All States") {
    VStack(spacing: 50) {
        ConnectionStatusView(status: .disconnected)
        ConnectionStatusView(status: .connecting)
        ConnectionStatusView(status: .connected)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Design.Colors.surfaceBackground)
}

#Preview("Connected - Dark") {
    ConnectionStatusView(status: .connected)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.surfaceBackground)
        .preferredColorScheme(.dark)
}
