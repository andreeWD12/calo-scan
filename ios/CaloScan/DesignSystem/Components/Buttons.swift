import SwiftUI

/// Pulsante principale a tutta larghezza.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(DS.Palette.onBrand)
            .background(DS.Palette.brand.opacity(isEnabled ? 1 : 0.4), in: .rect(cornerRadius: DS.Radius.m))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(DS.Motion.quick, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(DS.Palette.textPrimary)
            .background(DS.Palette.surfaceMuted, in: .rect(cornerRadius: DS.Radius.m))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// Pulsante principale che mostra uno spinner durante un'operazione asincrona.
struct LoadingButton: View {
    let title: LocalizedStringKey
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(DS.Palette.onBrand) }
            }
        }
        .buttonStyle(.primary)
        .disabled(isLoading)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isLoading ? Text("In corso") : Text(""))
    }
}
