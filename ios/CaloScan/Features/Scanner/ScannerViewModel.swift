import Foundation
import Observation
import CaloScanCore

/// Una riga modificabile del risultato di scansione.
struct DraftItem: Identifiable, Hashable {
    let id: UUID
    var detectedName: String
    var food: FoodItem?
    var grams: Double
    var confidence: Confidence?
    var ingredients: [String]

    var nutrients: Nutrients? { food.map { $0.per100g.scaled(per100gTo: grams) } }
}

@Observable
@MainActor
final class ScannerViewModel {
    enum Phase: Equatable {
        case capture
        case analyzing
        case result
        case failed(APIError)
    }

    private(set) var phase: Phase = .capture
    private(set) var imageData: Data?
    private(set) var scanID: UUID?
    private(set) var questions: [String] = []
    private(set) var overallConfidence: Confidence?
    private(set) var isSaving = false
    private(set) var hasAIConsent: Bool?
    /// Descrizione inviata per l'ultima analisi (nil se l'analisi è partita solo dalla foto).
    private(set) var analyzedDescription: String?
    /// Testo che l'utente sta scrivendo nel foglio "Descrivi il piatto".
    var descriptionDraft = ""
    var items: [DraftItem] = []
    var mealType: MealType = .suggested()
    /// L'utente segna il pasto come sgarro: conta nelle calorie e compare a parte nelle statistiche.
    var isCheatMeal = false
    var saveError: APIError?

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    func loadConsent() async {
        hasAIConsent = (try? await services.account.consents())?.aiImageAnalysis ?? false
    }

    func grantAIConsent() async {
        do {
            var consents = try await services.account.consents()
            consents.aiImageAnalysis = true
            try await services.account.update(consents: consents)
            hasAIConsent = true
        } catch {
            phase = .failed(APIError.from(error))
        }
    }

    // MARK: Analisi

    func analyze(rawImage: Data) async {
        guard let jpeg = ImageProcessor.prepareForUpload(rawImage) else {
            phase = .failed(.invalidInput(String(localized: "Immagine non valida.")))
            return
        }
        imageData = jpeg
        analyzedDescription = nil
        phase = .analyzing
        do {
            apply(try await services.scanner.analyze(jpegData: jpeg),
                  emptyMessage: String(localized: "Non abbiamo riconosciuto alimenti in questa foto. Prova a descrivere il piatto a parole, oppure inserisci il pasto manualmente."))
        } catch {
            phase = .failed(APIError.from(error))
        }
    }

    /// Analisi a partire dal testo, per quando la foto non basta o non c'è.
    /// Se c'è la foto di un tentativo precedente, viene inviata insieme al testo.
    func analyze(description: String) async {
        guard let text = FoodDescription.sanitize(description) else {
            phase = .failed(.invalidInput(String(localized: "Descrivi il piatto con qualche parola in più, per esempio \"pasta al pomodoro, un piatto medio\".")))
            return
        }
        analyzedDescription = text
        phase = .analyzing
        do {
            apply(try await services.scanner.analyze(description: text, jpegData: imageData),
                  emptyMessage: String(localized: "Non siamo riusciti a riconoscere alimenti da questa descrizione. Prova a indicare i singoli alimenti e le quantità, oppure cercali manualmente."))
        } catch {
            phase = .failed(APIError.from(error))
        }
    }

    private func apply(_ result: ScanResult, emptyMessage: String) {
        scanID = result.id
        questions = result.questions
        overallConfidence = Confidence(score: result.overallConfidenceScore)
        items = result.items.map {
            DraftItem(id: $0.id, detectedName: $0.detectedName, food: $0.matchedFood,
                      grams: $0.estimatedGrams, confidence: $0.confidence, ingredients: $0.ingredients)
        }
        phase = result.items.isEmpty ? .failed(.invalidInput(emptyMessage)) : .result
    }

    /// Origine del pasto salvato: la descrizione prevale se è stata usata.
    var mealSource: MealSource { analyzedDescription == nil ? .scan : .description }

    func retake() {
        phase = .capture
        imageData = nil
        analyzedDescription = nil
        items = []
        questions = []
        scanID = nil
    }

    // MARK: Modifica

    var totals: Nutrients { items.compactMap(\.nutrients).total }
    var unresolvedCount: Int { items.filter { $0.food == nil }.count }
    var canSave: Bool { !items.isEmpty && unresolvedCount == 0 && !isSaving }

    func update(_ item: DraftItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    /// L'utente chiude il suggerimento dell'AI senza rispondere.
    func dismissQuestions() { questions = [] }

    func remove(_ item: DraftItem) {
        items.removeAll { $0.id == item.id }
    }

    func add(food: FoodItem, grams: Double) {
        items.append(DraftItem(id: UUID(), detectedName: food.name, food: food, grams: grams,
                               confidence: nil, ingredients: []))
    }

    // MARK: Salvataggio

    /// Salva il pasto confermato dall'utente. Ritorna `true` se il salvataggio è riuscito.
    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        let mealItems = items.compactMap { item in item.food.map { MealItem(food: $0, grams: item.grams) } }
        let meal = Meal(type: mealType, loggedAt: .now, items: mealItems, source: mealSource, scanID: scanID,
                        isCheatMeal: isCheatMeal)
        do {
            try await services.meals.save(meal)
            // La foto resta solo sul telefono, come miniatura del pasto nel diario.
            if let imageData { await MealPhotoStore.shared.save(jpegData: imageData, for: meal.id) }
            return true
        } catch {
            saveError = APIError.from(error)
            return false
        }
    }
}
