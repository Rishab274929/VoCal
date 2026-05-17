//
//  Theme.swift
//  VoCal
//
//  Editorial-voice design system. Dark-first monochrome: ink on bone with
//  pure paper-white as the single emphasis signal. Matches the starfield-
//  on-black logo. New York (serif) display + SF Pro body.
//
//  Design-language pivot notes:
//   - Lime (voltage) and coral (pulse) hex constants are PRESERVED so any
//     remaining direct references in screens compile, but the canonical
//     accent is now `paper` (pure white) for emphasis and `smoke` for
//     de-emphasis. Use `bone` for an over-goal / subtle warning instead
//     of coral.
//   - Macros keep their hues — they're the only color in the system and
//     they map to a tangible thing (protein, carbs, fat) so removing them
//     would lose information, not just decoration.
//

import SwiftUI

enum Theme {

    // MARK: Palette — black and white, hairline grays, macro accents only

    enum Palette {
        // Surfaces
        static let ink           = Color(hex: 0x0A0A0B)   // base canvas — deep black
        static let inkRaised     = Color(hex: 0x121214)   // first elevation
        static let inkSurface    = Color(hex: 0x18181C)   // cards / sheets
        static let inkElevated   = Color(hex: 0x1F1F24)   // popovers / chips
        static let hairline      = Color(hex: 0x1F1E1B)   // subtle borders
        static let hairlineStrong = Color(hex: 0x2E2D29)  // visible borders

        // Text
        static let paper         = Color(hex: 0xFFFFFF)   // pure white — hero numerals & emphasis
        static let bone          = Color(hex: 0xF5F2EA)   // primary on dark — warm off-white
        static let ash           = Color(hex: 0xBDBBB2)   // secondary on dark
        static let smoke         = Color(hex: 0x86847B)   // tertiary on dark

        // Legacy accent constants — PRESERVED so screens that still reference
        // them compile. New work MUST use `paper` for emphasis. The old lime
        // and coral are not deleted because doing so would break a long tail
        // of view files we're not touching in this pivot.
        static let voltage       = Color(hex: 0xE5FF59)   // legacy lime
        static let voltageDeep   = Color(hex: 0xB7D03A)
        static let pulse         = Color(hex: 0xFF5436)   // legacy coral
        static let pulseDeep     = Color(hex: 0xE03C1F)

        // Macros — the only chromatic information in the system. These map
        // to actual nutrients (P/C/F/fiber) so they survive the pivot.
        static let protein       = Color(hex: 0xFF7A8A)   // dusty rose
        static let carbs         = Color(hex: 0xFFD466)   // amber
        static let fat           = Color(hex: 0x7BB7FF)   // soft sky
        static let fiber         = Color(hex: 0xB7D03A)   // moss

        // Legacy aliases — point `brand`/`energy` at paper so any
        // unaudited consumers get the new monochrome accent automatically.
        static let canvas        = ink
        static let surface       = inkSurface
        static let surfaceElevated = inkElevated
        static let brand         = paper
        static let brandSoft     = paper.opacity(0.6)
        static let brandDeep     = bone
        static let energy        = paper
    }

    // MARK: Spacing — generous, editorial rhythm

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let sm:  CGFloat = 12
        static let md:  CGFloat = 18
        static let lg:  CGFloat = 28
        static let xl:  CGFloat = 44
        static let xxl: CGFloat = 64
    }

    enum Radius {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 14
        static let md: CGFloat = 22
        static let lg: CGFloat = 30
        static let xl: CGFloat = 44
    }

    // MARK: Type — New York (serif) display + SF Pro body

    enum Font {
        // Hero serif numbers (kcal remaining, BF%) — uses iOS New York
        static func serif(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular, italic: Bool = false) -> SwiftUI.Font {
            let font = SwiftUI.Font.system(size: size, weight: weight, design: .serif)
            return italic ? font.italic() : font
        }

        // Editorial section heading (mid-size serif)
        static let editorial = SwiftUI.Font.system(size: 28, weight: .semibold, design: .serif)

        // Wordmark — small serif italic
        static let wordmark = SwiftUI.Font.system(size: 19, weight: .semibold, design: .serif).italic()

        // Tracked all-caps eyebrow label
        static let eyebrow = SwiftUI.Font.system(size: 10, weight: .semibold, design: .default)

        // Body + UI (SF Pro)
        static let body = SwiftUI.Font.system(size: 15, weight: .regular)
        static let bodyMedium = SwiftUI.Font.system(size: 15, weight: .medium)
        static let bodyBold = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let caption = SwiftUI.Font.system(size: 12, weight: .regular)
        static let captionMedium = SwiftUI.Font.system(size: 12, weight: .medium)

        // Monospaced digit chunky number (used for macro counters)
        static func mono(_ size: CGFloat, weight: SwiftUI.Font.Weight = .medium) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    // MARK: Gradients
    //
    // Monochrome pivot: voltage/pulse gradients keep their names because
    // legacy callers reference them, but they now render as pure white
    // ramps so the screen reads as one editorial monochrome surface.

    static let voltageGradient = LinearGradient(
        colors: [Palette.paper, Palette.paper, Palette.bone],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let pulseGradient = LinearGradient(
        colors: [Palette.paper, Palette.bone, Palette.ash],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let inkGradient = LinearGradient(
        colors: [Palette.ink, Palette.inkRaised],
        startPoint: .top,
        endPoint: .bottom
    )

    static let micGradient = voltageGradient
    static let brandGradient = voltageGradient
}

// MARK: - View extensions

extension View {
    /// Editorial card — soft elevated surface with hairline border.
    func card(padding: CGFloat = Theme.Spacing.md, radius: CGFloat = Theme.Radius.md) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.Palette.inkSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                    )
            )
    }

    /// Tracked, tiny, all-caps eyebrow text styling.
    ///
    /// `tracking(1.6)` distributes letter-spacing around each glyph, which
    /// pushes the FIRST character ~0.8pt past its frame's leading edge.
    /// On a left-aligned container at the screen edge that bleeds INTO
    /// the screen's rounded corner / safe-area gutter, so we add a tiny
    /// fixed leading offset to keep the first glyph fully inside.
    func eyebrow(_ color: Color = Theme.Palette.smoke) -> some View {
        self
            .font(Theme.Font.eyebrow)
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.leading, 1)
    }
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
