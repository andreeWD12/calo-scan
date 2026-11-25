import SwiftUI
import CaloScanCore

/// Alimento inserito dall'utente con i valori dell'etichetta (per 100 g). Funziona anche senza la
/// ricerca nei database: il cibo viene salvato nel pasto con i suoi valori, come quelli trovati.
struct CustomFoodView: View {
    let onCreate: (FoodItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?

    private var cleanName: String { name.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    private var nameError: String? {
        cleanName.count > ShoppingItem.nameMaxLength ? String(localized: "Il nome è troppo lungo.") : nil
    }
    private var kcalError: String? {
        guard let kcal else { return nil }
        return (0...900).contains(kcal) ? nil : String(localized: "Le calorie per 100 g vanno da 0 a 900.")
    }
    private var macroError: String? {
        let values = [protein, carbs, fat].compactMap { $0 }
        if values.contains(where: { !(0...100).contains($0) }) { return String(localized: "Ogni valore va da 0 a 100 g.") }
        if values.reduce(0, +) > 100 { return String(localized: "Proteine, carboidrati e grassi insieme non possono superare 100 g.") }
        return nil
    }
    private var canSave: Bool {
        !cleanName.isEmpty && nameError == nil && kcal != nil && kcalError == nil && macroError == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledField(label: "Nome", error: nameError) {
                        TextField("Es. Biscotti integrali", text: $name)
                    }
                }
                Section {
                    NumericField(label: "Calorie", value: $kcal, unit: "kcal", fractionDigits: 0, error: kcalError)
                    NumericField(label: "Proteine", value: $protein, unit: "g")
                    NumericField(label: "Carboidrati", value: $carbs, unit: "g")
                    NumericField(label: "Grassi", value: $fat, unit: "g", error: macroError)
                } header: {
                    Text("Valori per 100 g")
                } footer: {
                    Text("Li trovi nella tabella nutrizionale sulla confezione. Se non conosci un valore, lascialo vuoto: conterà come 0.")
                }
            }
            .navigationTitle("Nuovo alimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continua") {
                        let food = FoodItem(name: cleanName,
                                            per100g: Nutrients(kcal: kcal ?? 0, proteinG: protein ?? 0,
                                                               carbsG: carbs ?? 0, fatG: fat ?? 0),
                                            source: .custom)
                        onCreate(food)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
