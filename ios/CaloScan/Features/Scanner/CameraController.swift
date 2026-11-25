import AVFoundation
import UIKit
import SwiftUI

/// Gestione della fotocamera posteriore su una coda dedicata (AVFoundation non è thread-safe).
final class CameraController: NSObject, @unchecked Sendable {
    enum CameraError: LocalizedError {
        case unavailable, captureFailed
        var errorDescription: String? {
            switch self {
            case .unavailable: String(localized: "Fotocamera non disponibile su questo dispositivo.")
            case .captureFailed: String(localized: "Impossibile scattare la foto. Riprova.")
            }
        }
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.caloscan.camera")
    private let output = AVCapturePhotoOutput()
    private var continuation: CheckedContinuation<Data, Error>?

    static var authorization: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func configure() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard session.inputs.isEmpty else { cont.resume(); return }
                session.beginConfiguration()
                session.sessionPreset = .photo
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    cont.resume(throwing: CameraError.unavailable)
                    return
                }
                session.addInput(input)
                session.addOutput(output)
                output.maxPhotoQualityPrioritization = .balanced
                session.commitConfiguration()
                cont.resume()
            }
        }
    }

    func start() { queue.async { [session] in if !session.isRunning { session.startRunning() } } }
    func stop() { queue.async { [session] in if session.isRunning { session.stopRunning() } } }

    func capture() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                guard continuation == nil else { cont.resume(throwing: CameraError.captureFailed); return }
                continuation = cont
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async { [self] in
            let cont = continuation
            continuation = nil
            if let data { cont?.resume(returning: data) } else { cont?.resume(throwing: CameraError.captureFailed) }
        }
    }
}

/// Anteprima live della fotocamera.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Prepara la foto per l'invio: ridimensiona e ricodifica in JPEG.
/// La ricodifica elimina tutti i metadati EXIF, inclusa la posizione GPS (minimizzazione dei dati).
enum ImageProcessor {
    static func prepareForUpload(_ data: Data, maxDimension: CGFloat = 1280, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
