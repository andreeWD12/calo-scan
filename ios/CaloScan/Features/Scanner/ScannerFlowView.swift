import SwiftUI
import PhotosUI
@preconcurrency import AVFoundation

/// Flusso di scansione a schermo intero: fotocamera → analisi → risultato modificabile → salvataggio.
struct ScannerFlowView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: ScannerViewModel
    @State private var showManualEntry = false
    @State private var showPaywall = false
    @State private var showDescribe = false

    init(services: AppServices) {
        _model = State(initialValue: ScannerViewModel(services: services))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .capture:
                    if app.entitlements.scansRemaining == 0 {
                        QuotaReachedView(plan: app.entitlements.plan,
                                         onUpgrade: { showPaywall = true },
                                         onManual: { showManualEntry = true })
                    } else if model.hasAIConsent == false {
                        AIConsentView(onAccept: { Task { await model.grantAIConsent() } },
                                      onDescribe: { showDescribe = true },
                                      onManual: { showManualEntry = true })
                    } else {
                        CaptureView(onImage: { data in Task { await model.analyze(rawImage: data) } },
                                    onDescribe: { showDescribe = true },
                                    onManual: { showManualEntry = true })
                    }
                case .analyzing:
                    AnalyzingView(imageData: model.imageData, description: model.analyzedDescription)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                case .result:
                    ScanResultView(model: model, services: app.services,
                                   onDescribe: { showDescribe = true }) {
                        app.mealSaved(model.mealType, source: model.mealSource)
                        dismiss()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                case .failed(let error):
                    ScanFailureView(error: error,
                                    hasPhoto: model.imageData != nil,
                                    onRetry: { model.retake() },
                                    onDescribe: { showDescribe = true },
                                    onManual: { showManualEntry = true },
                                    onUpgrade: { showPaywall = true })
                }
            }
            .animation(DS.Motion.standard, value: model.phase)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .sensoryFeedback(trigger: model.phase) { _, phase in
            switch phase {
            case .result: .success
            case .failed: .error
            default: nil
            }
        }
        .task { await model.loadConsent() }
        .sheet(isPresented: $showManualEntry) {
            AddFoodFlowView(services: app.services, mealType: model.mealType) {
                app.mealSaved(model.mealType)
                dismiss()
            }
        }
        .sheet(isPresented: $showDescribe) {
            DescribeFoodView(text: $model.descriptionDraft, includesPhoto: model.imageData != nil) { text in
                Task { await model.analyze(description: text) }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(services: app.services, highlight: app.entitlements.plan == .plus ? .pro : .plus)
        }
    }
}

// MARK: - Fotocamera

private struct CaptureView: View {
    let onImage: (Data) -> Void
    let onDescribe: () -> Void
    let onManual: () -> Void

    @State private var camera = CameraController()
    @State private var status = CameraController.authorization
    @State private var cameraError: String?
    @State private var isCapturing = false
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if status == .authorized && cameraError == nil {
                CameraPreview(session: camera.session).ignoresSafeArea()
                FramingGuide()
            } else {
                permissionPrompt
            }
            VStack {
                Spacer()
                Text("Inquadra il piatto dall'alto, con una buona luce")
                    .font(DS.Font.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Spacing.s).padding(.vertical, DS.Spacing.xs)
                    .background(.black.opacity(0.45), in: .capsule)
                Button(action: onDescribe) {
                    Label("Descrivi a parole", systemImage: "text.bubble")
                        .font(DS.Font.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Spacing.m).frame(minHeight: 44)
                        .background(.ultraThinMaterial.opacity(0.9), in: .capsule)
                        .environment(\.colorScheme, .dark)
                }
                .buttonStyle(.pressable)
                .padding(.top, DS.Spacing.xs)
                .accessibilityHint(Text("Scrivi cosa hai mangiato invece di scattare una foto"))
                controls
            }
            .padding(.bottom, DS.Spacing.l)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await setUp() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { onImage(data) }
                pickerItem = nil
            }
        }
    }

    private var controls: some View {
        HStack {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                CircleIcon(name: "photo.on.rectangle")
            }
            .accessibilityLabel(Text("Scegli una foto dalla libreria"))
            Spacer()
            Button {
                Task {
                    isCapturing = true
                    defer { isCapturing = false }
                    do { onImage(try await camera.capture()) }
                    catch { cameraError = error.localizedDescription }
                }
            } label: {
                ZStack {
                    Circle().fill(.white).frame(width: 74, height: 74)
                    Circle().strokeBorder(.black.opacity(0.15), lineWidth: 3).frame(width: 64, height: 64)
                    if isCapturing { ProgressView().tint(.black) }
                }
            }
            .disabled(status != .authorized || isCapturing)
            .accessibilityLabel(Text("Scatta la foto"))
            .sensoryFeedback(.impact, trigger: isCapturing)
            Spacer()
            Button(action: onManual) { CircleIcon(name: "magnifyingglass") }
                .accessibilityLabel(Text("Cerca un alimento manualmente"))
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.top, DS.Spacing.m)
    }


    @ViewBuilder
    private var permissionPrompt: some View {
        VStack(spacing: DS.Spacing.m) {
            Image(systemName: "camera").font(.system(size: 44)).foregroundStyle(.white.opacity(0.8))
            if let cameraError {
                Text(cameraError).foregroundStyle(.white).multilineTextAlignment(.center)
            } else if status == .denied || status == .restricted {
                Text("Per scansionare i piatti consenti l'accesso alla fotocamera nelle Impostazioni. In alternativa puoi scegliere una foto dalla libreria.")
                    .foregroundStyle(.white).multilineTextAlignment(.center)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Apri Impostazioni", destination: url)
                        .buttonStyle(.borderedProminent).tint(DS.Palette.brand)
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .padding(DS.Spacing.xl)
    }

    private func setUp() async {
        if status == .notDetermined {
            _ = await CameraController.requestAccess()
            status = CameraController.authorization
        }
        guard status == .authorized else { return }
        do {
            try await camera.configure()
            camera.start()
        } catch {
            cameraError = error.localizedDescription
        }
    }
}

/// Riquadro guida per centrare il piatto.
private struct FramingGuide: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 32)
            .strokeBorder(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
            .aspectRatio(1, contentMode: .fit)
            .padding(DS.Spacing.xl)
            .accessibilityHidden(true)
    }
}

// MARK: - Stati

private struct AnalyzingView: View {
    let imageData: Data?
    let description: String?
    @State private var pulse = false
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DS.Spacing.l) {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 220, height: 220)
                    .clipShape(.rect(cornerRadius: DS.Radius.l))
                    .overlay(alignment: .top) {
                        if !reduceMotion {
                            LinearGradient(colors: [.clear, DS.Palette.brand.opacity(0.55), .clear],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 60)
                                .offset(y: sweep ? 190 : -60)
                                .blendMode(.plusLighter)
                        }
                    }
                    .clipShape(.rect(cornerRadius: DS.Radius.l))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.l)
                        .strokeBorder(DS.Palette.brand, lineWidth: 3).opacity(pulse ? 1 : 0.3))
                    .accessibilityHidden(true)
            }
            if let description {
                Text("“\(description)”")
                    .font(DS.Font.callout.italic())
                    .foregroundStyle(DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(DS.Spacing.m)
                    .frame(maxWidth: .infinity)
                    .background(DS.Palette.surface, in: .rect(cornerRadius: DS.Radius.l))
            }
            ProgressView()
            Text(description == nil ? "Analisi del piatto in corso…" : "Analisi della descrizione in corso…").font(DS.Font.headline)
            Text("Riconosciamo gli alimenti, stimiamo le porzioni e cerchiamo i valori nutrizionali nei database.")
                .font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary).multilineTextAlignment(.center)
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Palette.background.ignoresSafeArea())
        .onAppear {
            guard !reduceMotion else { pulse = true; return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { sweep = true }
        }
    }
}

private struct ScanFailureView: View {
    let error: APIError
    let hasPhoto: Bool
    let onRetry: () -> Void
    let onDescribe: () -> Void
    let onManual: () -> Void
    let onUpgrade: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Analisi non riuscita", systemImage: "camera.metering.unknown")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            if case .quotaExceeded = error {
                Button("Scopri i piani Premium", action: onUpgrade).buttonStyle(.borderedProminent)
            } else {
                Button(action: onDescribe) {
                    Label("Descrivi il piatto a parole", systemImage: "text.bubble")
                }
                .buttonStyle(.borderedProminent)
                Button(hasPhoto ? "Scatta di nuovo" : "Usa la fotocamera", action: onRetry)
            }
            Button("Cerca gli alimenti manualmente", action: onManual)
        }
        .tint(DS.Palette.brand)
        .background(DS.Palette.background.ignoresSafeArea())
    }
}

private struct QuotaReachedView: View {
    let plan: Plan
    let onUpgrade: () -> Void
    let onManual: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Scansioni di oggi esaurite", systemImage: "hourglass")
        } description: {
            Text(plan == .pro
                 ? "Hai usato tutte le scansioni disponibili oggi. Si rinnovano domani."
                 : "Hai usato le scansioni AI incluse oggi nel piano \(plan.displayName). Si rinnovano domani, oppure puoi passare a un piano superiore.")
        } actions: {
            if plan < .pro {
                Button("Scopri i piani Premium", action: onUpgrade).buttonStyle(.borderedProminent)
            }
            Button("Inserisci manualmente", action: onManual)
        }
        .tint(DS.Palette.brand)
        .background(DS.Palette.background.ignoresSafeArea())
    }
}

/// Consenso all'invio delle foto al fornitore AI, chiesto al primo utilizzo se non dato in onboarding.
private struct AIConsentView: View {
    let onAccept: () -> Void
    let onDescribe: () -> Void
    let onManual: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Image(systemName: "sparkles.rectangle.stack").font(.system(size: 44)).foregroundStyle(DS.Palette.brand)
            Text("Analisi delle foto con l'AI").font(DS.Font.title)
            Text("Per riconoscere gli alimenti, la foto del piatto viene inviata in modo cifrato al nostro fornitore di intelligenza artificiale. La foto non contiene la tua posizione, non viene usata per addestrare modelli e viene cancellata automaticamente dopo l'analisi entro il periodo indicato nell'informativa.")
                .foregroundStyle(DS.Palette.textSecondary)
            Link("Leggi l'informativa sulla privacy", destination: LegalLinks.privacyPolicy)
                .font(DS.Font.callout.weight(.semibold))
            Spacer()
            Button("Acconsento e continuo", action: onAccept).buttonStyle(.primary)
            Button("Descrivi il piatto senza foto", action: onDescribe).buttonStyle(.secondary)
            Button("Inserisci manualmente", action: onManual)
                .font(DS.Font.callout.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
            Text("Puoi revocare il consenso in qualsiasi momento da Impostazioni → Privacy.")
                .font(DS.Font.caption).foregroundStyle(DS.Palette.textTertiary)
        }
        .padding(DS.Spacing.screen)
        .background(DS.Palette.background.ignoresSafeArea())
    }
}

/// Pulsante tondo della fotocamera. È una View a sé perché l'etichetta di PhotosPicker non è sul main actor.
private struct CircleIcon: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 54, height: 54)
            .background(.white.opacity(0.18), in: .circle)
    }
}
