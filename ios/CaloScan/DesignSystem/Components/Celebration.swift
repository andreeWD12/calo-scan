import SwiftUI
import CaloScanCore

/// Testo e icona di un traguardo. Tono incoraggiante, mai colpevolizzante.
struct Celebration: Identifiable, Equatable {
    let id = UUID()
    let milestone: Milestone
    let title: String
    let message: String
    let symbol: String
    let tint: Color

    init(_ m: Milestone) {
        milestone = m
        switch m {
        case .dayOnTarget:
            title = String(localized: "Obiettivo di oggi raggiunto!")
            message = String(localized: "Sei in linea con le calorie di oggi. È la costanza a fare la differenza: ottimo lavoro.")
            symbol = "target"; tint = DS.Palette.brand
        case .proteinReached:
            title = String(localized: "Proteine raggiunte")
            message = String(localized: "Hai raggiunto le proteine di oggi: aiutano la sazietà e i muscoli.")
            symbol = "bolt.heart.fill"; tint = DS.Palette.protein
        case .allMainMeals:
            title = String(localized: "Giornata completa")
            message = String(localized: "Colazione, pranzo e cena registrati: così statistiche e consigli sono più precisi.")
            symbol = "checkmark.seal.fill"; tint = DS.Palette.brand
        case .streak(let n):
            title = String(localized: "\(n) giorni di fila!")
            message = n >= 7
                ? String(localized: "Registri i pasti da \(n) giorni consecutivi. Questa è un'abitudine vera: complimenti!")
                : String(localized: "Le abitudini nascono così, un giorno alla volta. Continua domani.")
            symbol = "flame.fill"; tint = DS.Palette.streak
        case .welcomeBack:
            title = String(localized: "Bentornato!")
            message = String(localized: "Riprendere conta più che non fermarsi mai. Un pasto alla volta.")
            symbol = "hand.wave.fill"; tint = DS.Palette.breakfast
        case .habitTip(let i):
            let tip = Self.habitTips[i % Self.habitTips.count]
            title = tip.0; message = tip.1; symbol = tip.2; tint = DS.Palette.brand
        case .weightHalfway:
            title = String(localized: "Sei a metà strada!")
            message = String(localized: "Hai fatto metà del percorso verso il tuo peso obiettivo. Continua con calma: un ritmo graduale è quello che dura.")
            symbol = "flag.fill"; tint = DS.Palette.dinner
        case .weightGoalReached:
            title = String(localized: "Peso obiettivo raggiunto!")
            message = String(localized: "Ce l'hai fatta. Ora puoi impostare il mantenimento dal Profilo per consolidare il risultato.")
            symbol = "trophy.fill"; tint = DS.Palette.streak
        }
    }

    /// Consigli sulle abitudini, uno al giorno al primo pasto registrato.
    static let habitTips: [(String, String, String)] = [
        (String(localized: "Buon inizio!"), String(localized: "Registrare i pasti subito dopo averli mangiati rende il diario più preciso."), "clock.fill"),
        (String(localized: "Un bicchiere d'acqua"), String(localized: "Tieni una bottiglia d'acqua a portata di mano: è più facile bere durante la giornata."), "drop.fill"),
        (String(localized: "Metà piatto di verdura"), String(localized: "Riempire metà piatto di verdura aiuta la sazietà con poche calorie."), "leaf.fill"),
        (String(localized: "Mangia con calma"), String(localized: "Mangiare lentamente aiuta ad accorgersi quando si è sazi."), "tortoise.fill"),
        (String(localized: "Proteine a ogni pasto"), String(localized: "Una fonte di proteine a ogni pasto aiuta a restare sazi più a lungo."), "fork.knife"),
        (String(localized: "Spuntini pronti"), String(localized: "Frutta o yogurt a portata di mano rendono più facile scegliere bene quando hai fame."), "carrot.fill"),
        (String(localized: "Dormire bene conta"), String(localized: "Un buon sonno aiuta anche a gestire fame e voglie durante il giorno."), "moon.zzz.fill"),
        (String(localized: "Fai la spesa con la lista"), String(localized: "Una lista preparata prima aiuta a comprare ciò che ti serve davvero."), "cart.fill"),
        (String(localized: "Muoviti un po'"), String(localized: "Anche una passeggiata dopo i pasti è un'ottima abitudine."), "figure.walk"),
        (String(localized: "Niente sensi di colpa"), String(localized: "Un pasto abbondante non cancella i progressi: conta l'andamento della settimana."), "heart.fill"),
    ]
}

/// Coda dei traguardi da mostrare. Ognuno compare una volta (al giorno o per sempre, vedi `Milestone.isDaily`);
/// al massimo una festa a schermo pieno e due pop-up al giorno, per non diventare invadenti.
@Observable
@MainActor
final class CelebrationCenter {
    private(set) var current: Celebration?
    private var queue: [Celebration] = []
    private let defaults: UserDefaults
    private var dismissTask: Task<Void, Never>?

    nonisolated static let enabledKey = "celebrations.enabled"
    static let maxPopupsPerDay = 2
    static let maxCelebrationsPerDay = 1

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isEnabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }

    /// Mostra il primo traguardo non ancora visto, dopo `delay` (lascia finire il popup "Aggiunto a…").
    func offer(_ milestones: [Milestone], delay: Duration = .seconds(2.6), today: Date = .now) {
        guard isEnabled else { return }
        let day = Self.dayKey(today)
        guard let next = milestones.first(where: { canShow($0, day: day) }) else { return }
        record(next, day: day)
        let celebration = Celebration(next)
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.enqueue(celebration)
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            self?.present(next)
        }
    }

    private func enqueue(_ c: Celebration) {
        if current == nil { present(c) } else { queue.append(c) }
    }

    private func present(_ c: Celebration) {
        current = c
        dismissTask?.cancel()
        // I pop-up si chiudono da soli; le feste restano finché l'utente non tocca.
        guard !c.milestone.isCelebration else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func canShow(_ m: Milestone, day: String) -> Bool {
        let seen = m.isDaily ? "seen.\(m.key).\(day)" : "seen.\(m.key)"
        if defaults.bool(forKey: "celebrations.\(seen)") { return false }
        let countKey = m.isCelebration ? "celebrations.big.\(day)" : "celebrations.small.\(day)"
        let limit = m.isCelebration ? Self.maxCelebrationsPerDay : Self.maxPopupsPerDay
        return defaults.integer(forKey: countKey) < limit
    }

    private func record(_ m: Milestone, day: String) {
        let seen = m.isDaily ? "seen.\(m.key).\(day)" : "seen.\(m.key)"
        defaults.set(true, forKey: "celebrations.\(seen)")
        let countKey = m.isCelebration ? "celebrations.big.\(day)" : "celebrations.small.\(day)"
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}

// MARK: - Viste

extension View {
    /// Feste a schermo pieno e pop-up di incoraggiamento sopra il contenuto.
    func celebrationOverlay(_ center: CelebrationCenter) -> some View { modifier(CelebrationOverlay(center: center)) }
}

private struct CelebrationOverlay: ViewModifier {
    let center: CelebrationCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if let c = center.current, c.milestone.isCelebration {
                    CelebrationView(celebration: c, reduceMotion: reduceMotion) { center.dismiss() }
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if let c = center.current, !c.milestone.isCelebration {
                    EncouragementCard(celebration: c) { center.dismiss() }
                        .padding(.horizontal, DS.Spacing.s)
                        .padding(.top, DS.Spacing.xs)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : DS.Motion.bouncy, value: center.current)
            .sensoryFeedback(trigger: center.current) { _, new in
                guard let new else { return nil }
                return new.milestone.isCelebration ? .success : .impact(weight: .light)
            }
    }
}

/// Festa: velo scuro, coriandoli, icona che rimbalza dentro un anello che si riempie.
private struct CelebrationView: View {
    let celebration: Celebration
    let reduceMotion: Bool
    let onDismiss: () -> Void
    @State private var appeared = false
    @State private var bounce = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            if !reduceMotion {
                ConfettiView(colors: [celebration.tint, DS.Palette.breakfast, DS.Palette.dinner, DS.Palette.snack, DS.Palette.lunch])
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            VStack(spacing: DS.Spacing.m) {
                if case .streak(let days) = celebration.milestone {
                    StreakHero(days: days, reduceMotion: reduceMotion)
                } else {
                    ZStack {
                        Circle().fill(celebration.tint.opacity(0.15))
                        Circle().trim(from: 0, to: appeared ? 1 : 0)
                            .stroke(celebration.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: celebration.symbol)
                            .font(.system(size: 52, weight: .bold))
                            .foregroundStyle(celebration.tint.gradient)
                            .symbolEffect(.bounce, value: bounce)
                    }
                    .frame(width: 120, height: 120)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
                }

                Text(celebration.title)
                    .font(DS.Font.title).multilineTextAlignment(.center)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(celebration.message)
                    .font(DS.Font.callout).multilineTextAlignment(.center)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onDismiss) {
                    Text("Continua").font(DS.Font.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(celebration.tint)
            }
            .padding(DS.Spacing.l)
            .background(DS.Palette.surface, in: .rect(cornerRadius: DS.Radius.l))
            .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
            .padding(.horizontal, DS.Spacing.l)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
            .opacity(appeared || reduceMotion ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.7)) { appeared = true }
            Task { try? await Task.sleep(for: .seconds(0.4)); bounce += 1 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// Serie di giorni: fiamma viva che tremola, scintille che salgono, alone che pulsa,
/// numero che conta fino ai giorni raggiunti e pallini della settimana che si accendono uno dopo l'altro.
private struct StreakHero: View {
    let days: Int
    let reduceMotion: Bool
    @State private var shown = 0
    @State private var litDots = 0
    @State private var ignite = false
    @State private var start = Date.now

    private var dots: Int { min(days, 7) }

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
                ZStack {
                    // Alone che respira.
                    Circle()
                        .fill(RadialGradient(colors: [DS.Palette.streak.opacity(0.45), DS.Palette.streak.opacity(0)],
                                             center: .center, startRadius: 10, endRadius: 85))
                        .scaleEffect(1 + 0.08 * sin(t * 2.4))
                    // Anelli che si allargano e svaniscono.
                    if !reduceMotion {
                        ForEach(0..<2, id: \.self) { i in
                            let phase = (t * 0.7 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                            Circle().stroke(DS.Palette.streak.opacity(0.5 * (1 - phase)), lineWidth: 3)
                                .scaleEffect(0.55 + phase * 0.75)
                        }
                        Embers(time: t).frame(width: 150, height: 170).offset(y: -20)
                    }
                    // Fiamma che tremola.
                    Image(systemName: "flame.fill")
                        .font(.system(size: 76, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [DS.Palette.breakfast, DS.Palette.streak, .red],
                                                        startPoint: .top, endPoint: .bottom))
                        .scaleEffect(x: 1 + 0.04 * sin(t * 9), y: 1 + 0.09 * sin(t * 7 + 1), anchor: .bottom)
                        .rotationEffect(.degrees(4 * sin(t * 5)), anchor: .bottom)
                        .shadow(color: DS.Palette.streak.opacity(0.6), radius: 14 + 6 * sin(t * 3))
                        .scaleEffect(ignite || reduceMotion ? 1 : 0.1, anchor: .bottom)
                        .offset(y: 6)
                }
                .frame(width: 160, height: 160)
            }

            Text("\(shown)")
                .font(.system(size: 54, weight: .heavy, design: .rounded))
                .foregroundStyle(DS.Palette.streak)
                .contentTransition(.numericText(value: Double(shown)))
                .monospacedDigit()
                .accessibilityLabel(Text("\(days) giorni di fila"))

            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    Circle()
                        .fill(i < litDots ? DS.Palette.streak : DS.Palette.separator)
                        .frame(width: 14, height: 14)
                        .scaleEffect(i < litDots ? 1.15 : 0.85)
                        .overlay {
                            if i < litDots {
                                Image(systemName: "checkmark").font(.system(size: 7, weight: .black)).foregroundStyle(.white)
                            }
                        }
                }
            }
            .accessibilityHidden(true)
            .opacity(dots > 0 ? 1 : 0)
        }
        .task { await play() }
    }

    private func play() async {
        guard !reduceMotion else { shown = days; litDots = dots; ignite = true; return }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) { ignite = true }
        try? await Task.sleep(for: .seconds(0.35))
        // Conta fino ai giorni raggiunti (al massimo ~25 passi, così anche 365 dura poco più di un secondo).
        let steps = min(days, 25)
        for k in 1...max(steps, 1) {
            withAnimation(.snappy(duration: 0.12)) { shown = Int((Double(days) * Double(k) / Double(max(steps, 1))).rounded()) }
            try? await Task.sleep(for: .milliseconds(steps > 10 ? 45 : 90))
        }
        for i in 1...max(dots, 1) where dots > 0 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { litDots = i }
            try? await Task.sleep(for: .milliseconds(110))
        }
    }
}

/// Scintille che salgono dalla fiamma.
private struct Embers: View {
    let time: Double
    private static let seeds: [(x: Double, speed: Double, delay: Double, size: Double)] = (0..<18).map { i in
        let r = Double((i * 7919) % 100) / 100
        return (x: (r - 0.5) * 0.7, speed: 0.6 + r * 0.6, delay: Double(i) / 18, size: 3 + r * 4)
    }

    var body: some View {
        Canvas { context, size in
            for s in Self.seeds {
                let p = (time * s.speed + s.delay).truncatingRemainder(dividingBy: 1)
                let x = size.width / 2 + s.x * size.width + sin(time * 3 + s.delay * 10) * 8
                let y = size.height * (0.85 - p * 0.85)
                let rect = CGRect(x: x - s.size / 2, y: y - s.size / 2, width: s.size * (1 - p * 0.5), height: s.size * (1 - p * 0.5))
                context.opacity = 1 - p
                context.fill(Path(ellipseIn: rect), with: .color(p < 0.4 ? DS.Palette.breakfast : DS.Palette.streak))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Pop-up breve di incoraggiamento o sulle abitudini (si chiude da solo dopo 5 secondi).
private struct EncouragementCard: View {
    let celebration: Celebration
    let onDismiss: () -> Void
    @State private var bounce = 0

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.s) {
            Image(systemName: celebration.symbol)
                .font(.title2).foregroundStyle(celebration.tint)
                .frame(width: 40, height: 40)
                .background(celebration.tint.opacity(0.15), in: .circle)
                .symbolEffect(.bounce, value: bounce)
            VStack(alignment: .leading, spacing: 2) {
                Text(celebration.title).font(DS.Font.headline).foregroundStyle(DS.Palette.textPrimary)
                Text(celebration.message).font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(DS.Palette.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel(Text("Chiudi"))
        }
        .padding(DS.Spacing.s)
        .background(.regularMaterial, in: .rect(cornerRadius: DS.Radius.l))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .onAppear { bounce += 1 }
        .accessibilityElement(children: .combine)
    }
}

/// Coriandoli che cadono per qualche secondo (disegnati con Canvas, nessuna immagine).
private struct ConfettiView: View {
    let colors: [Color]
    @State private var start = Date.now
    private let pieces: [Piece] = (0..<70).map { _ in Piece() }

    struct Piece {
        let x = Double.random(in: 0...1)
        let delay = Double.random(in: 0...0.6)
        let speed = Double.random(in: 0.25...0.5)
        let sway = Double.random(in: 10...40)
        let spin = Double.random(in: 2...7)
        let size = Double.random(in: 6...11)
        let colorIndex = Int.random(in: 0..<5)
        let isCircle = Bool.random()
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                for p in pieces {
                    let progress = (t - p.delay) * p.speed
                    guard progress > 0, progress < 1.3 else { continue }
                    let x = p.x * size.width + sin(t * p.spin) * p.sway
                    let y = -20 + progress * (size.height + 40)
                    var piece = context
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(t * p.spin))
                    piece.opacity = progress > 1 ? max(0, 1 - (progress - 1) / 0.3) : 1
                    let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.isCircle ? p.size : p.size / 2)
                    let shape = p.isCircle ? Path(ellipseIn: rect) : Path(rect)
                    piece.fill(shape, with: .color(colors[p.colorIndex % colors.count]))
                }
            }
        }
    }
}
