import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case home, diary, scanner, progress, profile

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .diary: "Diario"
        case .scanner: "Scanner"
        case .progress: "Progressi"
        case .profile: "Profilo"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .diary: "book.closed"
        case .scanner: "camera.viewfinder"
        case .progress: "chart.line.uptrend.xyaxis"
        case .profile: "person.crop.circle"
        }
    }
}

/// Navigazione principale a 5 sezioni. Lo Scanner è il pulsante centrale in evidenza
/// e apre la fotocamera a schermo intero (con effetto zoom dal pulsante su iOS 18).
/// Le sezioni restano in memoria: cambiando tab si ritrova la stessa posizione di scroll.
struct MainTabView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: AppTab = .home
    @State private var showScanner = false
    @Namespace private var scannerZoom

    var body: some View {
        ZStack {
            tab(.home) { HomeView(services: app.services, onScan: { showScanner = true }) }
            tab(.diary) { DiaryView(services: app.services) }
            tab(.progress) { ProgressScreen(services: app.services) }
            tab(.profile) { ProfileView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TabBar(selection: $selection, zoomNamespace: scannerZoom, onScan: { showScanner = true })
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScannerFlowView(services: app.services)
                .zoomTransition(sourceID: "scanner", in: scannerZoom)
        }
        .onChange(of: app.router.pending) { _, link in handle(link) }
        .onAppear { handle(app.router.pending) }
    }

    /// Ogni sezione resta montata; quella attiva entra con una leggera dissolvenza e scala.
    private func tab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        let isActive = selection == tab
        return content()
            .opacity(isActive ? 1 : 0)
            .scaleEffect(isActive || reduceMotion ? 1 : 0.985)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Motion.snappy, value: selection)
    }

    /// Apre la schermata richiesta da una notifica o da un link `caloscan://`.
    private func handle(_ link: DeepLink?) {
        guard let link else { return }
        switch link {
        case .scanner:
            showScanner = true
            app.router.pending = nil
        case .home: selection = .home; app.router.pending = nil
        case .diary: selection = .diary; app.router.pending = nil
        case .profile: selection = .profile; app.router.pending = nil
        case .progress: selection = .progress; app.router.pending = nil
        // Questi li completa la sezione stessa (apre il coach o il foglio del peso) e azzera `pending`.
        case .coach: selection = .home
        case .logWeight: selection = .progress
        case .professionalPlan: selection = .profile
        }
    }
}

private extension View {
    /// Zoom dal pulsante Scanner alla fotocamera (iOS 18+); su iOS 17 resta la presentazione standard.
    @ViewBuilder
    func zoomTransition(sourceID: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomSource(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}

private struct TabBar: View {
    @Binding var selection: AppTab
    let zoomNamespace: Namespace.ID
    let onScan: () -> Void
    @State private var scanTaps = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                if tab == .scanner {
                    scanButton
                } else {
                    tabButton(tab)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.top, DS.Spacing.xs)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .symbolVariant(selection == tab ? .fill : .none)
                    .font(.system(size: 20))
                    .symbolEffect(.bounce.down, value: selection == tab)
                    .contentTransition(.symbolEffect(.replace))
                Text(tab.title).font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(selection == tab ? DS.Palette.brand : DS.Palette.textTertiary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var scanButton: some View {
        Button {
            scanTaps += 1
            onScan()
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle().fill(DS.Palette.brand)
                        .shadow(color: DS.Palette.brand.opacity(0.35), radius: 10, y: 4)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(DS.Palette.onBrand)
                }
                .frame(width: 62, height: 62)
                .symbolEffect(.bounce, value: scanTaps)
                .zoomSource(id: "scanner", in: zoomNamespace)
                .offset(y: -14)
                .padding(.bottom, -14)
                Text("Scanner").font(.caption2.weight(.semibold)).foregroundStyle(DS.Palette.brand)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.impact(weight: .medium), trigger: scanTaps)
        .accessibilityLabel(Text("Scansiona il tuo piatto"))
    }
}
