import SwiftUI

// MARK: - App Font (Plus Jakarta Sans)

enum AppFont {
    static let regular = "PlusJakartaSans-Regular"
    static let medium = "PlusJakartaSans-Medium"
    static let semiBold = "PlusJakartaSans-SemiBold"
    static let bold = "PlusJakartaSans-Bold"
}

extension Font {
    static func jakarta(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .bold, .heavy, .black:
            .custom(AppFont.bold, size: size)
        case .semibold:
            .custom(AppFont.semiBold, size: size)
        case .medium:
            .custom(AppFont.medium, size: size)
        default:
            .custom(AppFont.regular, size: size)
        }
    }

    // MARK: - Semantic Sizes

    static var jakartaLargeTitle: Font { .jakarta(34, weight: .bold) }
    static var jakartaTitle: Font { .jakarta(28, weight: .bold) }
    static var jakartaTitle2: Font { .jakarta(22, weight: .semibold) }
    static var jakartaTitle3: Font { .jakarta(20, weight: .semibold) }
    static var jakartaHeadline: Font { .jakarta(17, weight: .semibold) }
    static var jakartaBody: Font { .jakarta(17) }
    static var jakartaCallout: Font { .jakarta(16) }
    static var jakartaSubheadline: Font { .jakarta(15) }
    static var jakartaFootnote: Font { .jakarta(13) }
    static var jakartaCaption: Font { .jakarta(12) }
    static var jakartaCaption2: Font { .jakarta(11) }
}
