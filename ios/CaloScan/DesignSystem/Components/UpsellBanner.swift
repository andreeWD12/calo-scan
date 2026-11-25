import SwiftUI

/// Invito all'upgrade non invasivo: una scheda compatta sopra la barra delle sezioni,
/// che non blocca l'app, si chiude con la X o da sola dopo qualche secondo.
struct UpsellBanner: View {
    let prompt: UpsellPrompt
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.s) {
            Image(systemName: prompt.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DS.Palette.brand)
                .frame(width: 40, height: 40)
                .background(DS.Palette.brandSoft, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.title).font(DS.Font.callout.weight(.semibold)).foregroundStyle(DS.Palette.textPrimary)
                Text(prompt.message).font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onOpen) {
                    Text(prompt.target == .plus ? "Scopri Plus" : "Scopri Pro")
                        .font(DS.Font.caption.weight(.bold))
                        .foregroundStyle(DS.Palette.brand)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Chiudi"))
        }
        .padding(.leading, DS.Spacing.s)
        .padding(.vertical, DS.Spacing.xs)
        .background(.regularMaterial, in: .rect(cornerRadius: DS.Radius.l))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.l).strokeBorder(DS.Palette.separator.opacity(0.6)))
        .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
    }
}
