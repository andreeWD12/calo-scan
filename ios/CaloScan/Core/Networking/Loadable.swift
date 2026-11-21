import Foundation

/// Stato standard di ogni schermata che carica dati.
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case empty
    case failed(APIError)

    var value: Value? { if case .loaded(let v) = self { v } else { nil } }
    var isLoading: Bool { if case .loading = self { true } else { false } }
}

extension Loadable: Equatable where Value: Equatable {}
