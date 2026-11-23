import Foundation
import CaloScanCore

/// Ricerca alimenti (funzione `food-search`): USDA FoodData Central e Open Food Facts, con cache sul server.
struct SupabaseFoodSearchService: FoodSearchService {
    let functions: EdgeFunctionClient

    private struct QueryBody: Encodable, Sendable { let query: String }
    private struct BarcodeBody: Encodable, Sendable { let barcode: String }
    private struct SearchResponse: Decodable { let foods: [FoodItem] }
    private struct LookupResponse: Decodable { let food: FoodItem? }

    func search(_ query: String) async throws -> [FoodItem] {
        let response: SearchResponse = try await functions.invoke(.foodSearch, body: QueryBody(query: query))
        return response.foods
    }

    func lookup(barcode: String) async throws -> FoodItem? {
        let response: LookupResponse = try await functions.invoke(.foodSearch, body: BarcodeBody(barcode: barcode))
        return response.food
    }
}

/// Analisi del pasto (funzione `analyze-food`). La foto arriva già ridimensionata e senza EXIF
/// (`ImageProcessor`); il server non la salva. Il fuso orario serve a contare le scansioni "di oggi".
struct SupabaseScanService: ScanService {
    let functions: EdgeFunctionClient

    private struct Body: Encodable, Sendable {
        let image: String?
        let description: String?
        let timeZone: String
    }

    func analyze(jpegData: Data) async throws -> ScanResult {
        try await functions.invoke(.analyzeFood, body: Body(image: jpegData.base64EncodedString(), description: nil,
                                                             timeZone: TimeZone.current.identifier))
    }

    func analyze(description: String, jpegData: Data?) async throws -> ScanResult {
        try await functions.invoke(.analyzeFood, body: Body(image: jpegData?.base64EncodedString(), description: description,
                                                             timeZone: TimeZone.current.identifier))
    }
}

/// Piano e utilizzo di oggi (funzione `get-entitlements`). Gli acquisti arrivano con la Fase 8.
struct SupabaseEntitlementService: EntitlementService {
    let functions: EdgeFunctionClient

    private struct Body: Encodable, Sendable { let timeZone: String }

    func refresh() async throws -> Entitlements {
        try await functions.invoke(.getEntitlements, body: Body(timeZone: TimeZone.current.identifier))
    }
}
