import SwiftUI
import PhotosUI
import AVFoundation

/// Flusso di scansione a schermo intero: fotocamera → analisi → risultato modificabile → salvataggio.
struct ScannerFlowView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: ScannerViewModel
    @State private var showManualEntry = false
    @State private var showPaywall = false

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
                                      onManual: { showManualEntry = true })
                    } else {
                        CaptureView(onImage: { data in Task { await model.analyze(rawImage: data) } },
                                    onManual: { showManualEntry = true })
                    }
                case .analyzing:
                    AnalyzingView(imageData: model.imageData)
                case .result:
                    ScanResultView(model: model, services: app.services) {
                        app.diaryDidChange()
                        dismiss()
                    }
                case .failed(let error):
                    ScanFailureView(error: error,
                                    onRetry: { model.retake() },
                                    onManual: { showManualEntry = true },
                                    onUpgrade: { showPaywall = true })
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .task { await model.loadConsent() }
        .sheet(isPresented: $showManualEntry) {
            AddFoodFlowView(services: app.services, mealType: model.mealType) {
                app.diaryDidChange()
                dismiss()
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
                circleIcon("photo.on.rectangle")
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
            Button(action: onManual) { circleIcon("magnifyingglass") }
                .accessibilityLabel(Text("Cerca un alimento manualmente"))
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.top, DS.Spacing.m)
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 54, height: 54)
            .background(.white.opacity(0.18), in: .circle)
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
    @State private var pulse = false

    var body: some View {
        VStack(spacing: DS.Spacing.l) {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 220, height: 220)
                    .clipShape(.rect(cornerRadius: DS.Radius.l))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.l)
                        .strokeBorder(DS.Palette.brand, lineWidth: 3).opacity(pulse ? 1 : 0.3))
                    .accessibilityHidden(true)
            }
            ProgressView()
            Text("Analisi del piatto in corso…").font(DS.Font.headline)
            Text("Riconosciamo gli alimenti, stimiamo le porzioni e cerchiamo i valori nutrizionali nei database.")
                .font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary).multilineTextAlignment(.center)
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Palette.background.ignoresSafeArea())
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
    }
}

private struct ScanFailureView: View {
    let error: APIError
    let onRetry: () -> Void
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
                Button("Scatta di nuovo", action: onRetry).buttonStyle(.borderedProminent)
            }
            Button("Inserisci manualmente", action: onManual)
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
            Button("Inserisci manualmente", action: onManual).buttonStyle(.secondary)
            Text("Puoi revocare il consenso in qualsiasi momento da Impostazioni → Privacy.")
                .font(DS.Font.caption).foregroundStyle(DS.Palette.textTertiary)
        }
        .padding(DS.Spacing.screen)
        .background(DS.Palette.background.ignoresSafeArea())
    }
}
