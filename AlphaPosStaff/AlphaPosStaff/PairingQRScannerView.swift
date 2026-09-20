import AVFoundation
import SwiftUI

struct PairingQRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> PairingQRScannerViewController {
        let controller = PairingQRScannerViewController()
        controller.onScan = onScan
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: PairingQRScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: PairingQRScannerViewController, coordinator: ()) {
        uiViewController.stopScanning()
    }
}

final class PairingQRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "alphapos.pairing.camera")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false
    private var isStopping = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.configureCamera() : self?.fail("Camera permission is required to scan the pairing QR code")
                }
            }
        default:
            fail("Enable Camera access for AlphaPosStaff in Settings")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Release the camera as soon as the scanner leaves the screen so it is
        // free for the Timecard evidence camera or Apple's Camera app.
        stopScanning()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Restart only when the session was already configured (inputs present)
        // but is not currently running — e.g. returning to this screen.
        guard !session.inputs.isEmpty, !session.isRunning else { return }
        sessionQueue.async { [self] in self.session.startRunning() }
    }

    private func configureCamera() {
        guard let camera = AVCaptureDevice.default(for: .video) else {
            fail("Camera is not available on this device")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else { throw ScannerError.configuration }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { throw ScannerError.configuration }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.insertSublayer(layer, at: 0)
            previewLayer = layer
            sessionQueue.async { [self] in self.session.startRunning() }
        } catch {
            fail("Unable to start the camera scanner")
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasScanned,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        hasScanned = true

        // Do not mutate the SwiftUI sheet while AVCaptureSession is still
        // delivering metadata. The old ordering dismissed the sheet first,
        // then tore down the session asynchronously, which could race with
        // the next view tree being created and terminate the app on device.
        stopScanning { [weak self] in
            DispatchQueue.main.async {
                self?.onScan?(value)
            }
        }
    }

    func stopScanning(completion: (() -> Void)? = nil) {
        guard !isStopping else {
            completion?()
            return
        }
        isStopping = true
        // Retain the controller until the capture session is fully stopped and
        // its inputs/outputs have been removed. Using a weak capture here can
        // allow SwiftUI to release the controller while this queue is still
        // tearing down AVFoundation, which produces an over-release warning and
        // can terminate the app on a real device.
        sessionQueue.async { [self] in
            if self.session.isRunning { self.session.stopRunning() }
            // Fully tear the session down so the capture device is released.
            // Merely calling `stopRunning()` leaves the AVCaptureDeviceInput
            // holding the camera, which starves a subsequent UIImagePicker /
            // capture session (e.g. the Timecard evidence camera) and results
            // in a black preview.
            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            for output in self.session.outputs {
                self.session.removeOutput(output)
            }
            self.isStopping = false
            DispatchQueue.main.async { completion?() }
        }
    }

    deinit {
        // Safety net in case SwiftUI never routes through dismantle: make sure
        // the camera is not left locked by this scanner.
        stopScanning()
    }

    private func fail(_ message: String) {
        onError?(message)
    }

    private enum ScannerError: Error { case configuration }
}
