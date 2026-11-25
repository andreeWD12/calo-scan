import SwiftUI
import CaloScanCore

extension MealType {
    /// Colore del pasto, per icone e accenti.
    var tint: Color {
        switch self {
        case .breakfast: DS.Palette.breakfast
        case .lunch: DS.Palette.lunch
        case .dinner: DS.Palette.dinner
        case .snack: DS.Palette.snack
        }
    }

    /// Simbolo pieno per l'icona colorata.
    var filledSymbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }

    /// Invito mostrato quando il pasto è ancora vuoto.
    var emptyHint: LocalizedStringKey {
        switch self {
        case .breakfast: "Inizia la giornata: tocca + per aggiungere la colazione"
        case .lunch: "Tocca + per aggiungere il pranzo"
        case .dinner: "Tocca + per aggiungere la cena"
        case .snack: "Uno spuntino? Tocca + per aggiungerlo"
        }
    }
}

/// Icona del pasto in un cerchio sfumato del suo colore.
struct MealIcon: View {
    let type: MealType
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: type.filledSymbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [type.tint.opacity(0.85), type.tint],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .circle)
            .shadow(color: type.tint.opacity(0.3), radius: 6, y: 3)
            .accessibilityHidden(true)
    }
}

/// Anello piccolo per un macronutriente, con valore al centro.
struct MacroRing: View {
    let title: LocalizedStringKey
    let consumed: Double
    let target: Int
    let tint: Color
    var size: CGFloat = 64

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double { target > 0 ? min(consumed / Double(target), 1) : 0 }

    var body: some View {
        VStack(spacing: DS.Spacing.xxs) {
            ZStack {
                Circle().stroke(tint.opacity(0.15), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(consumed.rounded()))")
                        .font(DS.Font.headline.monospacedDigit())
                        .foregroundStyle(DS.Palette.textPrimary)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                    Text("/\(target) g").font(.caption2.monospacedDigit()).foregroundStyle(DS.Palette.textTertiary)
                }
                .padding(8)
            }
            .frame(width: size, height: size)
            Text(title).font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .onAppear { withMotion(DS.Motion.fill.delay(0.15), reduceMotion: reduceMotion) { shown = progress } }
        .onChange(of: progress) { _, new in withMotion(DS.Motion.fill, reduceMotion: reduceMotion) { shown = new } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(Int(consumed.rounded())) grammi su \(target)"))
    }
}

/// Serie di giorni consecutivi con almeno un pasto registrato. Premia la costanza, non le calorie.
struct StreakPill: View {
    let days: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .symbolEffect(.bounce, value: reduceMotion ? 0 : days)
            Text("\(days)").font(DS.Font.headline.monospacedDigit()).contentTransition(.numericText())
        }
        .foregroundStyle(DS.Palette.streak)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(DS.Palette.streak.opacity(0.12), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(days == 1 ? "1 giorno di fila con pasti registrati" : "\(days) giorni di fila con pasti registrati"))
    }
}

/// Miniatura della foto del pasto, salvata solo su questo iPhone (vedi `MealPhotoStore`).
struct MealThumbnail: View {
    let image: UIImage
    var size: CGFloat = 40

    var body: some View {
        Image(uiImage: image).resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: DS.Radius.s))
            .accessibilityHidden(true)
    }
}
