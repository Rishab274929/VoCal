//
//  Theme.swift
//  VoCal
//
//  Editorial-voice design system. Dark-first, ink + lime + coral, with
//  New York (serif) display + SF Pro body. Every token is opinionated.
//

import SwiftUI

enum Theme {

    // MARK: Palette — ink-on-paper, with two electric accents

    enum Palette {
        // Surfaces
        static let ink           = Color(hex: 0x0A0A0B)   // base canvas
        static let inkRaised     = Color(hex: 0x121214)   // first elevation
        static let inkSurface    = Color(hex: 0x18181C)   // cards / sheets
        static let inkElevated   = Color(hex: 0x1F1F24)   // popovers / chips
        static let hairline      = Color.white.opacity(0.07)
        static let hairlineStrong = Color.white.opacity(0.13)

        // Text
        static let bone          = Color(hex: 0xF6F4EC)   // primary on dark — warm ivory
        static let ash           = Color(hex: 0xBDBBB2)   // secondary on dark
        static let smoke         = Color(hex: 0x86847B)   // tertiary on dark

        // Brand voltage
        static let voltage       = Color(hex: 0xE5FF59)   // lime — the "voice" accent
        static let voltageDeep   = Color(hex: 0xB7D03A)
        static let pulse         = Color(hex: 0xFF5436)   // coral — the "energy" accent
        static let pulseDeep     = Color(hex: 0xE03C1F)

        // Macros — chosen to harmonize with ink + voltage
        static let protein       = Color(hex: 0xFF7A8A)   // dusty rose
        static let carbs         = Color(hex: 0xFFD466)   // amber
        static let fat           = Color(hex: 0x7BB7FF)   // soft sky
        static let fiber         = Color(hex: 0xB7D03A)   // moss

        // Legacy aliases (some callers import these names)
        static let canvas        = ink
        static let surface       = inkSurface
        static let surfaceElevated = inkElevated
        static let brand         = voltage
        static let brandSoft     = voltage.opacity(0.6)
        static let brandDeep     = voltageDeep
        static let energy        = pulse
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

    static let voltageGradient = LinearGradient(
        colors: [Color(hex: 0xF6FF80), Palette.voltage, Palette.voltageDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let pulseGradient = LinearGradient(
        colors: [Color(hex: 0xFF8264), Palette.pulse, Palette.pulseDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let inkGradient = LinearGradient(
        colors: [Palette.ink, Palette.inkRaised],
        startPoint: .top,
        endPoint: .bottom
    )

    static let micGradient = pulseGradient
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
    func eyebrow(_ color: Color = Theme.Palette.smoke) -> some View {
        self
            .font(Theme.Font.eyebrow)
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(color)
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
