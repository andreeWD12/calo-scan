import SwiftUI

/// Anello di avanzamento calorico. Oltre il 100% l'anello resta pieno e cambia colore.
struct CalorieRing: View {
    let consumed: Double
    let target: Int
    var lineWidth: CGFloat = 16

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double { target > 0 ? consumed / Double(target) : 0 }
    private var remaining: Double { Double(target) - consumed }

    var body: some View {
        ZStack {
            Circle().stroke(DS.Palette.surfaceMuted, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(shown, 1))
                .stroke(progress > 1.1 ? DS.Palette.warning : DS.Palette.brand,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .onAppear { withMotion(DS.Motion.fill, reduceMotion: reduceMotion) { shown = progress } }
                .onChange(of: progress) { _, new in withMotion(DS.Motion.fill, reduceMotion: reduceMotion) { shown = new } }
            VStack(spacing: 2) {
                Text(Format.kcalNumber(abs(remaining)))
                    .font(DS.Font.metricLarge)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                Text(remaining >= 0 ? LocalizedStringKey("kcal rimanenti") : LocalizedStringKey("kcal oltre l'obiettivo"))
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .padding(lineWidth * 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Calorie"))
        .accessibilityValue(Text("\(Format.kcal(consumed)) consumate su \(Format.kcal(Double(target))). \(remaining >= 0 ? "Rimanenti" : "Oltre l'obiettivo"): \(Format.kcal(abs(remaining)))"))
    }
}

/// Barra di avanzamento di un macronutriente.
struct MacroBar: View {
    let title: LocalizedStringKey
    let consumed: Double
    let target: Int
    let tint: Color

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double { target > 0 ? min(consumed / Double(target), 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.textSecondary)
                Spacer()
                Text("\(Int(consumed.rounded()))/\(target) g")
                    .font(DS.Font.caption.monospacedDigit())
                    .foregroundStyle(DS.Palette.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Palette.surfaceMuted)
                    Capsule().fill(tint).frame(width: geo.size.width * shown)
                        .onAppear { withMotion(DS.Motion.fill, reduceMotion: reduceMotion) { shown = progress } }
                        .onChange(of: progress) { _, new in withMotion(DS.Motion.fill, reduceMotion: reduceMotion) { shown = new } }
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(Int(consumed.rounded())) grammi su \(target)"))
    }
}

/// Riga compatta di macro (P · C · G) per pasti e alimenti.
struct MacroInline: View {
    let protein: Double
    let carbs: Double
    let fat: Double

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            label("P", protein, DS.Palette.protein)
            label("C", carbs, DS.Palette.carbs)
            label("G", fat, DS.Palette.fat)
        }
        .font(DS.Font.caption.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Proteine \(Int(protein.rounded())) grammi, carboidrati \(Int(carbs.rounded())) grammi, grassi \(Int(fat.rounded())) grammi"))
    }

    private func label(_ letter: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(letter) \(Int(value.rounded())) g").foregroundStyle(DS.Palette.textSecondary)
        }
    }
}
