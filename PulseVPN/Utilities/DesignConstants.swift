import SwiftUI

// MARK: - Design Constants

enum Design {

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let pill: CGFloat = 100
    }

    // MARK: - Sizes

    enum Size {
        static let connectButtonDiameter: CGFloat = 150
        static let connectRingDiameter: CGFloat = 200
        static let statusDotSize: CGFloat = 10
        static let serverRowHeight: CGFloat = 64
        static let iconSize: CGFloat = 24
        static let flagSize: CGFloat = 32
        static let mapCardHeight: CGFloat = 160
        static let mapCardHeightExpanded: CGFloat = 340
    }

    // MARK: - Colors

    enum Colors {
        static let connected = teal
        static let connecting = Color.orange
        static let disconnected = Color(red: 0.45, green: 0.55, blue: 0.7)
        static let failed = Color.red

        static let accent = Color(red: 0.25, green: 0.55, blue: 1.0)
        static let accentDark = Color(red: 0.15, green: 0.35, blue: 0.8)

        static let teal = Color(red: 0.0, green: 0.55, blue: 0.55)

        #if os(iOS)
        static let surfaceBackground = Color(uiColor: .systemBackground)
        static let surfaceCard = Color(uiColor: .secondarySystemBackground)
        static let surfaceCardHover = Color(uiColor: .tertiarySystemBackground)
        static let textPrimary = Color(uiColor: .label)
        static let textSecondary = Color(uiColor: .secondaryLabel)
        static let textTertiary = Color(uiColor: .tertiaryLabel)
        static let separator = Color(uiColor: .separator)
        #else
        static let surfaceBackground = Color(nsColor: .windowBackgroundColor)
        static let surfaceCard = Color(nsColor: .controlBackgroundColor)
        static let surfaceCardHover = Color(nsColor: .underPageBackgroundColor)
        static let textPrimary = Color(nsColor: .labelColor)
        static let textSecondary = Color(nsColor: .secondaryLabelColor)
        static let textTertiary = Color(nsColor: .tertiaryLabelColor)
        static let separator = Color(nsColor: .separatorColor)
        #endif

        static let premium = Color(red: 1.0, green: 0.75, blue: 0.2)

        static func statusColor(for status: ConnectionStatus) -> Color {
            switch status {
            case .connected: return connected
            case .connecting, .disconnecting: return connecting
            case .disconnected: return disconnected
            case .failed: return failed
            }
        }
    }

    // MARK: - Animation

    enum Animation {
        static let springDefault = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.75)
        static let springQuick = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let springBouncy = SwiftUI.Animation.spring(response: 0.6, dampingFraction: 0.6)
        static let easeDefault = SwiftUI.Animation.easeInOut(duration: 0.3)
    }
}
