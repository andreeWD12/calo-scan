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
/// e apre la fotocamera a schermo intero invece di cambiare tab.
struct MainTabView: View {
    @Environment(AppState.self) private var app
    @State private var selection: AppTab = .home
    @State private var showScanner = false

    var body: some View {
        TabView(selection: $selection) {
            HomeView(services: app.services, onScan: { showScanner = true })
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.home)
            DiaryView(services: app.services)
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.diary)
            ProgressScreen(services: app.services)
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.progress)
            ProfileView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.profile)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TabBar(selection: $selection, onScan: { showScanner = true })
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScannerFlowView(services: app.services)
        }
    }
}

private struct TabBar: View {
    @Binding var selection: AppTab
    let onScan: () -> Void

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
        Button(action: onScan) {
            VStack(spacing: 3) {
                ZStack {
                    Circle().fill(DS.Palette.brand)
                        .shadow(color: DS.Palette.brand.opacity(0.35), radius: 10, y: 4)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(DS.Palette.onBrand)
                }
                .frame(width: 62, height: 62)
                .offset(y: -14)
                .padding(.bottom, -14)
                Text("Scanner").font(.caption2.weight(.semibold)).foregroundStyle(DS.Palette.brand)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Scansiona il tuo piatto"))
    }
}
