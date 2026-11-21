import SwiftUI

/// Campo numerico con unità di misura; accetta la virgola decimale secondo la lingua del dispositivo.
struct NumericField: View {
    let label: LocalizedStringKey
    @Binding var value: Double?
    let unit: String
    var fractionDigits: Int = 1
    var error: String? = nil

    var body: some View {
        LabeledField(label: label, error: error) {
            HStack {
                TextField("0", value: $value, format: .number.precision(.fractionLength(0...fractionDigits)))
                    .keyboardType(fractionDigits > 0 ? .decimalPad : .numberPad)
                    .font(DS.Font.headline.monospacedDigit())
                Text(unit).foregroundStyle(DS.Palette.textSecondary)
            }
        }
    }
}
