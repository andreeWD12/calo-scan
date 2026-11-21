import SwiftUI

/// Opzione selezionabile a scheda, usata nell'onboarding e nelle preferenze.
struct SelectionCard: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .frame(width: 32)
                        .foregroundStyle(isSelected ? DS.Palette.brand : DS.Palette.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DS.Font.headline).foregroundStyle(DS.Palette.textPrimary)
                    if let subtitle {
                        Text(subtitle).font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? DS.Palette.brand : DS.Palette.separator)
            }
            .padding(DS.Spacing.m)
            .background(isSelected ? DS.Palette.brandSoft : DS.Palette.surface, in: .rect(cornerRadius: DS.Radius.m))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.m)
                .strokeBorder(isSelected ? DS.Palette.brand : DS.Palette.separator, lineWidth: isSelected ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// Campo di testo con etichetta e messaggio d'errore.
struct LabeledField<Field: View>: View {
    let label: LocalizedStringKey
    var error: String? = nil
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(label).font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.textSecondary)
            field
                .padding(.horizontal, DS.Spacing.s)
                .frame(minHeight: 50)
                .background(DS.Palette.surface, in: .rect(cornerRadius: DS.Radius.s))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.s)
                    .strokeBorder(error == nil ? DS.Palette.separator : DS.Palette.danger, lineWidth: 1))
            if let error {
                Text(error).font(DS.Font.caption).foregroundStyle(DS.Palette.danger)
            }
        }
    }
}
