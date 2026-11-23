import SwiftUI
import UIKit

/// Token del design system CaloScan. Tutti i colori hanno una variante light e dark;
/// i contrasti testo/sfondo rispettano WCAG 2.1 AA (≥ 4.5:1 per il testo normale).
enum DS {

    enum Palette {
        /// Verde primario. Light #15894F (bianco sopra: 4.6:1). Dark #3DD68C (testo scuro sopra).
        static let brand = Color(light: 0x15894F, dark: 0x3DD68C)
        static let brandSoft = Color(light: 0xE3F4EA, dark: 0x173528)
        static let onBrand = Color(light: 0xFFFFFF, dark: 0x06140C)

        static let background = Color(light: 0xF5F7F6, dark: 0x0B0D0C)
        static let surface = Color(light: 0xFFFFFF, dark: 0x161A18)
        static let surfaceMuted = Color(light: 0xEDF1EF, dark: 0x1F2522)
        static let separator = Color(light: 0xDDE3E0, dark: 0x2A312D)

        static let textPrimary = Color(light: 0x0F1A14, dark: 0xF1F5F3)
        static let textSecondary = Color(light: 0x56645C, dark: 0xA3B0A8)
        static let textTertiary = Color(light: 0x7A8780, dark: 0x7D8A83)

        static let protein = Color(light: 0x2563EB, dark: 0x60A5FA)
        static let carbs = Color(light: 0xD97706, dark: 0xFBBF24)
        static let fat = Color(light: 0xDB2777, dark: 0xF472B6)

        static let warning = Color(light: 0xB45309, dark: 0xFBBF24)
        static let warningSoft = Color(light: 0xFEF3C7, dark: 0x3A2E10)
        static let danger = Color(light: 0xDC2626, dark: 0xF87171)
        static let success = brand

        /// Sfumatura leggera dietro le schermate (in alto un velo verde, in basso il fondo neutro).
        static let backgroundGlow = Color(light: 0xE6F5EC, dark: 0x0F1F17)
        static let backgroundGlowWarm = Color(light: 0xFFF4E5, dark: 0x1A160E)

        /// Un colore per ogni pasto, usato per icone e accenti.
        static let breakfast = Color(light: 0xD97706, dark: 0xFBBF24)
        static let lunch = Color(light: 0x15894F, dark: 0x3DD68C)
        static let dinner = Color(light: 0x6D4AD6, dark: 0xA78BFA)
        static let snack = Color(light: 0xDB2777, dark: 0xF472B6)

        /// Fiamma della serie di giorni registrati.
        static let streak = Color(light: 0xEA580C, dark: 0xFB923C)
    }

    /// Ombre morbide per le schede (in dark mode quasi invisibili, lì conta il contrasto della superficie).
    enum Shadow {
        static let card = Color(light: 0x0F1A14, dark: 0x000000).opacity(0.07)
        static let cardRadius: CGFloat = 14
        static let cardY: CGFloat = 6
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        /// Margine laterale delle schermate.
        static let screen: CGFloat = 20
    }

    enum Radius {
        static let s: CGFloat = 10
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let pill: CGFloat = 999
    }

    /// Tipografia basata sugli stili di sistema: segue Dynamic Type automaticamente.
    enum Font {
        static let display = SwiftUI.Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let title = SwiftUI.Font.system(.title2, design: .rounded, weight: .bold)
        static let headline = SwiftUI.Font.system(.headline, design: .rounded, weight: .semibold)
        static let body = SwiftUI.Font.body
        static let callout = SwiftUI.Font.callout
        static let caption = SwiftUI.Font.caption
        /// Numeri grandi (calorie, peso).
        static let metric = SwiftUI.Font.system(.title, design: .rounded, weight: .bold).monospacedDigit()
        static let metricLarge = SwiftUI.Font.system(size: 44, weight: .bold, design: .rounded).monospacedDigit()
    }

    /// Movimento in stile iOS: molle fisiche invece di curve a durata fissa.
    /// Ogni animazione passa da qui, così "Riduci movimento" viene rispettato ovunque.
    enum Motion {
        /// Transizioni di stato e layout.
        static let standard = Animation.smooth(duration: 0.4)
        /// Interazioni dirette (tocchi, selezioni): reattiva, senza rimbalzo.
        static let snappy = Animation.snappy(duration: 0.3)
        /// Elementi che "arrivano" (popup, conferme): leggero rimbalzo.
        static let bouncy = Animation.bouncy(duration: 0.5, extraBounce: 0.05)
        /// Grafici e anelli che si riempiono.
        static let fill = Animation.smooth(duration: 0.9)
        static let quick = Animation.easeOut(duration: 0.2)
        /// Ritardo tra elementi di una lista che entrano in sequenza.
        static let stagger: Double = 0.05
    }
}

extension Color {
    /// Colore dinamico light/dark da valori esadecimali RGB.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

/// Sfondo comune delle schermate: fondo neutro con due aloni sfumati, uno verde in alto
/// e uno caldo in basso. Decorativo, nascosto a VoiceOver.
struct AppBackground: View {
    var body: some View {
        ZStack {
            DS.Palette.background
            RadialGradient(colors: [DS.Palette.backgroundGlow, DS.Palette.backgroundGlow.opacity(0)],
                           center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [DS.Palette.backgroundGlowWarm.opacity(0.8), DS.Palette.backgroundGlowWarm.opacity(0)],
                           center: .bottomTrailing, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
