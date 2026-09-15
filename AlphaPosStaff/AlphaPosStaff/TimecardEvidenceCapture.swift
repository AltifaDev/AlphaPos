import SwiftUI
import UIKit
import Vision
import ImageIO
import AVFoundation

enum TimecardEvidenceError: LocalizedError {
    case cameraUnavailable
    case invalidImage
    case noFace
    case multipleFaces
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return "Camera is not available on this device."
        case .invalidImage: return "The captured image could not be read."
        case .noFace: return "No face was detected. Please face the camera and try again."
        case .multipleFaces: return "More than one face was detected. Only the employee may be in frame."
        case .compressionFailed: return "The evidence photo could not be compressed."
        }
    }
}

struct TimecardEvidenceCapture: UIViewControllerRepresentable {
    let onCapture: (Result<Data, Error>) -> Void
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// A camera is only truly usable when BOTH the picker source type reports
    /// available AND a real capture device is present. On the Simulator the
    /// source type can report `true` while no capture hardware exists, which
    /// produces the classic "black preview with shutter button" screen. We
    /// treat that case as unavailable so the user sees a clear message instead.
    private var isCameraUsable: Bool {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return false }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .unspecified
        )
        return !discovery.devices.isEmpty
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard isCameraUsable else {
            // Show an explicit, dismissable message instead of a black camera
            // preview (the failure mode on Simulators / devices with no camera).
            return CameraUnavailableViewController(
                message: TimecardEvidenceError.cameraUnavailable.localizedDescription,
                onClose: {
                    self.onCapture(.failure(TimecardEvidenceError.cameraUnavailable))
                    self.isPresented = false
                }
            )
        }
        let picker = TimecardImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        if UIImagePickerController.isCameraDeviceAvailable(.front) {
            picker.cameraDevice = .front
        }
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    /// UIImagePickerController owns the system camera session. Explicitly
    /// release its delegate when SwiftUI tears down the full-screen cover so a
    /// later launch of Apple's Camera app is not left competing for the device.
    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        guard let picker = uiViewController as? UIImagePickerController else { return }
        picker.delegate = nil
        picker.dismiss(animated: false)
        coordinator.parent.isPresented = false
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: TimecardEvidenceCapture
        init(parent: TimecardEvidenceCapture) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.onCapture(.failure(TimecardEvidenceError.invalidImage))
                parent.isPresented = false
                return
            }

            Task.detached(priority: .userInitiated) {
                do {
                    let data = try Self.validateAndCompress(image)
                    await MainActor.run {
                        self.parent.onCapture(.success(data))
                        self.parent.isPresented = false
                    }
                } catch {
                    await MainActor.run {
                        self.parent.onCapture(.failure(error))
                        self.parent.isPresented = false
                    }
                }
            }
        }

        nonisolated private static func validateAndCompress(_ image: UIImage) throws -> Data {
            guard let cgImage = image.cgImage else { throw TimecardEvidenceError.invalidImage }
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation),
                options: [:]
            )
            try handler.perform([request])
            let faceCount = request.results?.count ?? 0
            guard faceCount > 0 else { throw TimecardEvidenceError.noFace }
            guard faceCount == 1 else { throw TimecardEvidenceError.multipleFaces }

            // Attendance evidence is intentionally tiny: maximum 320 px on the
            // longest edge and low-quality JPEG. This is not a biometric template.
            let maxEdge: CGFloat = 320
            let longest = max(image.size.width, image.size.height)
            let scale = min(1, maxEdge / max(longest, 1))
            let target = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
            let renderer = UIGraphicsImageRenderer(size: target)
            let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
            guard let data = resized.jpegData(compressionQuality: 0.28) else {
                throw TimecardEvidenceError.compressionFailed
            }
            return data
        }
    }
}

private final class TimecardImagePickerController: UIImagePickerController {
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Break the delegate cycle and release the camera-backed picker as soon
        // as the evidence screen leaves the hierarchy.
        delegate = nil
    }
}

/// Full-screen fallback shown when no usable camera exists (e.g. Simulator or
/// a device whose camera is unavailable). Presents a readable message with an
/// explicit Close button instead of a black, unresponsive preview.
private final class CameraUnavailableViewController: UIViewController {
    private let message: String
    private let onClose: () -> Void
    private var didClose = false

    init(message: String, onClose: @escaping () -> Void) {
        self.message = message
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let icon = UIImageView(image: UIImage(systemName: "camera.fill.badge.ellipsis"))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = message
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .label
        label.font = .preferredFont(forTextStyle: .body)
        label.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.filled()
        config.title = "Close"
        config.cornerStyle = .large
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.close()
        })
        button.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [icon, label, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func close() {
        guard !didClose else { return }
        didClose = true
        onClose()
    }
}

private extension CGImagePropertyOrientation {
    nonisolated init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
