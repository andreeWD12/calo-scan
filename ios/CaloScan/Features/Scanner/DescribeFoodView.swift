import SwiftUI
import CaloScanCore

/// Foglio per descrivere a parole cosa si è mangiato, quando la foto non viene riconosciuta
/// o non si vuole scattarla. Il testo viene analizzato dall'AI sul server.
struct DescribeFoodView: View {
    @Binding var text: String
    /// C'è una foto da un tentativo precedente che verrà inviata insieme al testo.
    let includesPhoto: Bool
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private static let examples: [LocalizedStringResource] = [
        "Un piatto di pasta al pomodoro con parmigiano",
        "Petto di pollo alla griglia 150 g con insalata e un cucchiaio d'olio",
        "Yogurt greco con una banana e una manciata di mandorle",
    ]

    private var sanitized: String? { FoodDescription.sanitize(text) }
    private var count: Int { text.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Es. risotto ai funghi, un piatto medio, e un bicchiere di vino rosso",
                              text: $text, axis: .vertical)
                        .lineLimit(4...8)
                        .focused($focused)
                        .submitLabel(.done)
                        .accessibilityLabel(Text("Descrizione del pasto"))
                } header: {
                    Text("Cosa hai mangiato?")
                } footer: {
                    HStack(alignment: .top) {
                        Text("Elenca gli alimenti e, se puoi, le quantità o le porzioni (2 uova, una fetta di pane, un cucchiaio d'olio). Più dettagli dai, più la stima è precisa.")
                        Spacer(minLength: DS.Spacing.s)
                        Text("\(count)/\(FoodDescription.maxLength)")
                            .monospacedDigit()
                            .foregroundStyle(count > FoodDescription.maxLength ? DS.Palette.danger : DS.Palette.textTertiary)
                    }
                }

                Section("Esempi") {
                    ForEach(Array(Self.examples.enumerated()), id: \.offset) { _, example in
                        Button {
                            withAnimation(DS.Motion.snappy) { text = String(localized: example) }
                        } label: {
                            Label { Text(example).foregroundStyle(DS.Palette.textPrimary) }
                                icon: { Image(systemName: "text.quote").foregroundStyle(DS.Palette.brand) }
                        }
                    }
                }

                Section {
                    Label {
                        Text(includesPhoto
                             ? "La descrizione viene inviata in modo cifrato al nostro fornitore AI insieme alla foto che hai scattato. Non viene usata per addestrare modelli. I valori nutrizionali vengono poi dai database USDA e Open Food Facts."
                             : "La descrizione viene inviata in modo cifrato al nostro fornitore AI per riconoscere gli alimenti. Non viene usata per addestrare modelli. I valori nutrizionali vengono poi dai database USDA e Open Food Facts.")
                    } icon: {
                        Image(systemName: "lock.shield").foregroundStyle(DS.Palette.textSecondary)
                    }
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .navigationTitle("Descrivi il piatto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Analizza") {
                        guard let sanitized else { return }
                        dismiss()
                        onSubmit(sanitized)
                    }
                    .disabled(sanitized == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
