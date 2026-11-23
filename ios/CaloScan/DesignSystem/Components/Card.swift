import SwiftUI

/// Contenitore a scheda con angoli arrotondati.
struct Card<Content: View>: View {
    var padding: CGFloat = DS.Spacing.m
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.surface, in: .rect(cornerRadius: DS.Radius.l))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.l).strokeBorder(DS.Palette.separator.opacity(0.45), lineWidth: 0.5))
            .softShadow()
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Text(title).font(DS.Font.headline).foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
    }
}

/// Riquadro per un valore numerico con etichetta.
struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var caption: String? = nil
    var tint: Color = DS.Palette.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(title).font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
            Text(value).font(DS.Font.headline.monospacedDigit()).foregroundStyle(tint)
                .contentTransition(.numericText())
            if let caption {
                Text(caption).font(DS.Font.caption).foregroundStyle(DS.Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.s)
        .background(DS.Palette.surfaceMuted, in: .rect(cornerRadius: DS.Radius.m))
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Ombra morbida comune a schede e pulsanti principali.
    func softShadow() -> some View {
        shadow(color: DS.Shadow.card, radius: DS.Shadow.cardRadius, x: 0, y: DS.Shadow.cardY)
    }
}
