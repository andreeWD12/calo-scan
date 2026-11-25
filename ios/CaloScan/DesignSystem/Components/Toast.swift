import SwiftUI

/// Popup di conferma in stile iOS (capsula che scende dall'alto, come quelli di sistema per AirPods o Focus).
/// Mostrato per le azioni completate: pasto salvato, peso registrato, abbonamento attivato.
struct Toast: Identifiable, Equatable {
    enum Style: Equatable { case success, info, warning }
    let id = UUID()
    let style: Style
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil

    var resolvedSymbol: String {
        if let symbol { return symbol }
        switch style {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}

@Observable
@MainActor
final class ToastCenter {
    private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ toast: Toast, duration: Duration = .seconds(2.4)) {
        dismissTask?.cancel()
        current = toast
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func success(_ title: String, subtitle: String? = nil, symbol: String? = nil) {
        show(Toast(style: .success, title: title, subtitle: subtitle, symbol: symbol))
    }

    func dismiss() { current = nil }
}

private struct ToastView: View {
    let toast: Toast
    @State private var bounce = 0

    private var tint: Color {
        switch toast.style {
        case .success: DS.Palette.brand
        case .info: DS.Palette.protein
        case .warning: DS.Palette.warning
        }
    }

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            Image(systemName: toast.resolvedSymbol)
                .font(.title2)
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: bounce)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title).font(DS.Font.headline).foregroundStyle(DS.Palette.textPrimary)
                if let subtitle = toast.subtitle {
                    Text(subtitle).font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                }
            }
        }
        .padding(.leading, DS.Spacing.s)
        .padding(.trailing, DS.Spacing.l)
        .padding(.vertical, DS.Spacing.s)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .onAppear { bounce += 1 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

private struct ToastOverlayModifier: ViewModifier {
    @Bindable var center: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            ZStack {
                if let toast = center.current {
                    ToastView(toast: toast)
                        .id(toast.id)
                        .transition(reduceMotion ? .opacity
                                     : .move(edge: .top).combined(with: .scale(scale: 0.8, anchor: .top)).combined(with: .opacity))
                        .onTapGesture { center.dismiss() }
                        .gesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.height < 0 { center.dismiss() } })
                        .sensoryFeedback(toast.style == .warning ? .warning : .success, trigger: toast.id)
                        .onAppear {
                            UIAccessibility.post(notification: .announcement, argument: toast.title)
                        }
                }
            }
            .padding(.top, DS.Spacing.xs)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : DS.Motion.bouncy, value: center.current)
        }
    }
}

extension View {
    /// Mostra i popup di `center` sopra il contenuto. Applicato una volta alla radice dell'app.
    func toastOverlay(_ center: ToastCenter) -> some View { modifier(ToastOverlayModifier(center: center)) }
}
