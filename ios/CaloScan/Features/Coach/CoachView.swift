import SwiftUI
import CaloScanCore

/// AI Nutrition Coach: consigli del giorno e chat con l'assistente.
struct CoachView: View {
    @Environment(AppState.self) private var app
    @State private var model: CoachViewModel
    @State private var showPaywall = false
    @FocusState private var inputFocused: Bool

    init(services: AppServices) {
        _model = State(initialValue: CoachViewModel(coach: services.coach))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.s) {
                    AIDisclosure()
                    NavigationLink {
                        EatingStyleView(services: app.services)
                    } label: {
                        EatingStyleEntry(plan: app.entitlements.plan, current: app.profile?.eatingStyle?.style)
                    }
                    .buttonStyle(.pressable)
                    ForEach(model.insights) { InsightRow(insight: $0) }
                    conversation
                    if model.isSending { TypingIndicator().id("typing") }
                }
                .padding(DS.Spacing.screen)
            }
            .scrollDismissesKeyboard(.interactively)
            .animation(DS.Motion.bouncy, value: model.messages.value?.count)
            .animation(DS.Motion.standard, value: model.isSending)
            .onChange(of: model.messages.value?.count) { _, _ in
                if let id = model.messages.value?.last?.id {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
        .background(DS.Palette.background.ignoresSafeArea())
        .navigationTitle("Coach AI")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { inputBar }
        .task { await model.load() }
        .sheet(isPresented: $showPaywall) { PaywallView(services: app.services, highlight: .pro) }
        .alert("Messaggio non inviato",
               isPresented: Binding(get: { model.sendError != nil }, set: { if !$0 { model.sendError = nil } }),
               presenting: model.sendError) { error in
            if case .quotaExceeded = error { Button("Scopri i piani") { showPaywall = true } }
            Button("OK", role: .cancel) {}
        } message: { Text($0.localizedDescription) }
    }

    @ViewBuilder
    private var conversation: some View {
        switch model.messages {
        case .idle, .loading:
            LoadingStateView()
        case .failed(let error):
            ErrorStateView(error: error) { Task { await model.load() } }
        case .empty:
            EmptyView()
        case .loaded(let messages):
            if messages.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Prova a chiedere").font(DS.Font.caption.weight(.semibold))
                        .foregroundStyle(DS.Palette.textSecondary)
                    ForEach(CoachViewModel.suggestions, id: \.self) { s in
                        Button { Task { await model.send(s); app.coachMessageSent() } } label: {
                            Text(s).font(DS.Font.callout)
                                .padding(.horizontal, DS.Spacing.s).padding(.vertical, DS.Spacing.xs)
                                .background(DS.Palette.surface, in: .capsule)
                                .overlay(Capsule().strokeBorder(DS.Palette.separator))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, DS.Spacing.s)
            } else {
                ForEach(messages) { message in
                    MessageBubble(message: message)
                        .id(message.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity)
                                .combined(with: .scale(scale: 0.9, anchor: message.role == .user ? .bottomTrailing : .bottomLeading)),
                            removal: .opacity))
                }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: DS.Spacing.xs) {
                TextField("Scrivi una domanda…", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, DS.Spacing.s).padding(.vertical, 10)
                    .background(DS.Palette.surface, in: .rect(cornerRadius: DS.Radius.m))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.m).strokeBorder(DS.Palette.separator))
                Button { Task { await model.send(); app.coachMessageSent() } } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
                        .foregroundStyle(model.canSend ? DS.Palette.brand : DS.Palette.separator)
                }
                .disabled(!model.canSend)
                .sensoryFeedback(.impact(weight: .light), trigger: model.messages.value?.count)
                .accessibilityLabel(Text("Invia"))
            }
            let e = app.entitlements
            Text("\(max(e.coachMessagesLimitToday - e.coachMessagesUsedToday, 0)) messaggi disponibili oggi")
                .font(.caption2).foregroundStyle(DS.Palette.textTertiary)
        }
        .padding(.horizontal, DS.Spacing.screen)
        .padding(.vertical, DS.Spacing.xs)
        .background(.bar)
    }
}

/// Trasparenza sull'uso dell'AI (Regolamento UE 2024/1689, art. 50) e limiti dei consigli.
/// Accesso alla scelta dello stile alimentare (solo Pro; per Free e Plus mostra il lucchetto).
private struct EatingStyleEntry: View {
    let plan: Plan
    let current: EatingStyle?

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            Image(systemName: "fork.knife").font(.title3).foregroundStyle(DS.Palette.brand)
                .frame(width: 36, height: 36).background(DS.Palette.brandSoft, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Scegli lo stile alimentare").font(DS.Font.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(current?.title ?? String(localized: "Mediterranea, proteica, digiuno intermittente…"))
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
            }
            Spacer()
            if plan != .pro {
                Label("Pro", systemImage: "lock.fill").font(.caption.weight(.bold))
                    .foregroundStyle(DS.Palette.brand)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(DS.Palette.brandSoft, in: .capsule)
            } else {
                Image(systemName: "chevron.right").foregroundStyle(DS.Palette.textTertiary)
            }
        }
        .padding(DS.Spacing.s)
        .background(DS.Palette.surface, in: .rect(cornerRadius: DS.Radius.m))
    }
}

private struct AIDisclosure: View {
    var body: some View {
        EstimateNotice(text: "Stai parlando con un assistente basato sull'intelligenza artificiale. I suoi consigli sono informativi, possono contenere errori e non sostituiscono un medico, un dietista o un nutrizionista. Non fornisce diagnosi né diete terapeutiche.")
    }
}

private struct InsightRow: View {
    let insight: CoachInsight

    var body: some View {
        let symbol = switch insight.tone {
        case .positive: "hand.thumbsup"
        case .suggestion: "lightbulb"
        case .info: "chart.bar"
        }
        Label { Text(insight.text).font(DS.Font.callout) } icon: {
            Image(systemName: symbol).foregroundStyle(DS.Palette.brand)
        }
        .padding(DS.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.brandSoft, in: .rect(cornerRadius: DS.Radius.m))
    }
}

private struct MessageBubble: View {
    let message: CoachMessage

    var body: some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 48) }
            Text(AttributedString.markdown(message.text))   // il coach può usare Markdown semplice; mai come chiave di localizzazione
                .font(DS.Font.callout)
                .textSelection(.enabled)
                .padding(DS.Spacing.s)
                .foregroundStyle(isUser ? DS.Palette.onBrand : DS.Palette.textPrimary)
                .background(isUser ? DS.Palette.brand : DS.Palette.surface,
                            in: .rect(cornerRadius: DS.Radius.m))
            if !isUser { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isUser ? "Tu: \(message.text)" : "Coach: \(message.text)"))
    }
}

private struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().fill(DS.Palette.textTertiary).frame(width: 7, height: 7)
                    .opacity(0.3 + 0.7 * abs(sin(phase + Double(i) * 0.6)))
            }
        }
        .padding(DS.Spacing.s)
        .background(DS.Palette.surface, in: .capsule)
        .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi } }
        .accessibilityLabel(Text("Il coach sta scrivendo"))
    }
}
