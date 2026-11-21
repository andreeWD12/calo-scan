import SwiftUI
import CaloScanCore

/// Stato di caricamento con segnaposto animato.
struct LoadingStateView: View {
    var message: LocalizedStringKey = "Caricamento…"

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            ProgressView()
            Text(message).font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

/// Stato d'errore con azione "Riprova".
struct ErrorStateView: View {
    let error: APIError
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Qualcosa non ha funzionato", systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Riprova", action: retry).buttonStyle(.borderedProminent).tint(DS.Palette.brand)
        }
    }
}

/// Stato vuoto con invito all'azione.
struct EmptyStateView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(DS.Palette.brand)
            }
        }
    }
}

/// Avviso che i valori sono stime (mostrato su ogni risultato AI e sui calcoli metabolici).
struct EstimateNotice: View {
    let text: LocalizedStringKey

    var body: some View {
        Label { Text(text) } icon: { Image(systemName: "info.circle") }
            .font(DS.Font.caption)
            .foregroundStyle(DS.Palette.textSecondary)
            .padding(DS.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.surfaceMuted, in: .rect(cornerRadius: DS.Radius.s))
    }
}

struct ConfidenceBadge: View {
    let confidence: Confidence

    var body: some View {
        let (text, color): (LocalizedStringKey, Color) = switch confidence {
        case .high: ("Affidabilità alta", DS.Palette.brand)
        case .medium: ("Affidabilità media", DS.Palette.warning)
        case .low: ("Da verificare", DS.Palette.danger)
        }
        Text(text)
            .font(DS.Font.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, DS.Spacing.xs).padding(.vertical, 3)
            .background(color.opacity(0.12), in: .capsule)
    }
}

/// Badge del piano (Plus/Pro).
struct PlanBadge: View {
    let plan: Plan

    var body: some View {
        Text(plan.displayName.uppercased())
            .font(.caption2.weight(.heavy))
            .tracking(0.5)
            .foregroundStyle(DS.Palette.onBrand)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(DS.Palette.brand, in: .capsule)
            .accessibilityLabel(Text("Piano \(plan.displayName)"))
    }
}
