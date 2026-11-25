import SwiftUI

// Modificatori di animazione riutilizzabili. Tutti rispettano Impostazioni → Accessibilità →
// Movimento → "Riduci movimento": in quel caso gli spostamenti diventano semplici dissolvenze.

/// Entrata morbida dal basso con ritardo, per comporre sequenze "a cascata".
private struct AppearModifier: ViewModifier {
    let index: Int
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 14)
            .scaleEffect(visible || reduceMotion ? 1 : 0.98, anchor: .top)
            .onAppear {
                guard !visible else { return }
                withAnimation(DS.Motion.standard.delay(Double(index) * DS.Motion.stagger)) { visible = true }
            }
    }
}

/// Le schede si rimpiccioliscono e sfumano leggermente quando escono dallo schermo durante lo scroll.
private struct CardScrollModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.scrollTransition(.interactive, axis: .vertical) { view, phase in
                view
                    .opacity(phase.isIdentity ? 1 : 0.75)
                    .scaleEffect(phase.isIdentity ? 1 : 0.96)
            }
        }
    }
}

/// Stile di pressione per elementi toccabili personalizzati (schede, righe): si "abbassano" al tocco.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(DS.Motion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension View {
    /// Entrata in sequenza: `index` determina il ritardo.
    func appear(index: Int = 0) -> some View { modifier(AppearModifier(index: index)) }

    /// Effetto di profondità durante lo scroll.
    func cardScrollEffect() -> some View { modifier(CardScrollModifier()) }
}

/// Esegue un'animazione solo se "Riduci movimento" è disattivato, altrimenti applica il cambio subito.
@MainActor
func withMotion(_ animation: Animation = DS.Motion.standard, reduceMotion: Bool, _ body: () -> Void) {
    if reduceMotion { body() } else { withAnimation(animation, body) }
}
