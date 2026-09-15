import AVFoundation
import Combine
import CoreImage
import Foundation
import Vision

/// Performs employee verification from the front camera. This intentionally
/// does not use LocalAuthentication: Face ID only authenticates a person
/// enrolled as the device owner and cannot identify an AlphaPos employee.
final class EmployeeFaceVerifier: NSObject, ObservableObject {
    enum State: Equatable {
        case preparing
        case centerFace
        case turnHead
        case returnToCenter
        case matching
        case success(Float)
        case failure(String)
    }

    @Published private(set) var state: State = .preparing
    @Published private(set) var isCameraReady = false

    let session = AVCaptureSession()

    private let referenceEmbedding: Data
    private let captureQueue = DispatchQueue(label: "com.alphapos.employee-face-verifier", qos: .userInitiated)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var lastProcessedAt = Date.distantPast
    private var centeredFrameCount = 0
    private var turnedFrameCount = 0
    private var returnedFrameCount = 0
    private var similaritySamples: [Float] = []
    private var isFinished = false

    init(referenceEmbedding: Data) {
        self.referenceEmbedding = referenceEmbedding
        super.init()
    }

    func start() {
        guard !session.isRunning else { return }
        state = .preparing
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                granted ? self.configureAndStart() : self.fail("ไม่ได้รับอนุญาตให้ใช้กล้องหน้า")
            }
        default:
            fail("กรุณาอนุญาตการใช้กล้องใน Settings ก่อนลงเวลา")
        }
    }

    func stop() {
        captureQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func retry() {
        centeredFrameCount = 0
        turnedFrameCount = 0
        returnedFrameCount = 0
        similaritySamples.removeAll(keepingCapacity: true)
        isFinished = false
        lastProcessedAt = .distantPast
        state = .centerFace
        guard !session.inputs.isEmpty else {
            start()
            return
        }
        captureQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    private func configureAndStart() {
        captureQueue.async { [weak self] in
            guard let self else { return }
            do {
                self.session.beginConfiguration()
                do {
                    self.session.sessionPreset = .high
                    self.session.inputs.forEach(self.session.removeInput)
                    self.session.outputs.forEach(self.session.removeOutput)

                    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                        throw VerificationError.cameraUnavailable
                    }
                    let input = try AVCaptureDeviceInput(device: camera)
                    guard self.session.canAddInput(input) else { throw VerificationError.cameraUnavailable }
                    self.session.addInput(input)

                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ]
                    output.setSampleBufferDelegate(self, queue: self.captureQueue)
                    guard self.session.canAddOutput(output) else { throw VerificationError.cameraUnavailable }
                    self.session.addOutput(output)
                    if let connection = output.connection(with: .video) {
                        if connection.isVideoRotationAngleSupported(90) {
                            connection.videoRotationAngle = 90
                        }
                        if connection.isVideoMirroringSupported {
                            connection.automaticallyAdjustsVideoMirroring = false
                            connection.isVideoMirrored = true
                        }
                    }
                    self.session.commitConfiguration()
                } catch {
                    self.session.commitConfiguration()
                    throw error
                }
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isCameraReady = true
                    self.state = .centerFace
                }
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async {
            self.isFinished = true
            self.state = .failure(message)
        }
        stop()
    }

    private enum VerificationError: LocalizedError {
        case cameraUnavailable

        var errorDescription: String? {
            "ไม่พบกล้องหน้าที่พร้อมใช้งาน"
        }
    }
}

extension EmployeeFaceVerifier: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isFinished,
              Date().timeIntervalSince(lastProcessedAt) >= 0.18,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastProcessedAt = Date()

        let request = VNDetectFaceLandmarksRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
            let faces = request.results ?? []
            guard faces.count == 1, let face = faces.first else {
                resetProgress(message: !faces.isEmpty
                              ? "ต้องมีพนักงานเพียงหนึ่งคนในกรอบ"
                              : "จัดใบหน้าให้อยู่กลางกรอบ")
                return
            }
            guard isAcceptable(face) else {
                resetProgress(message: "ขยับใบหน้าให้อยู่กลางกรอบและเข้าใกล้กล้อง")
                return
            }
            advanceLiveness(with: face, pixelBuffer: pixelBuffer)
        } catch {
            fail("ตรวจจับใบหน้าไม่สำเร็จ: \(error.localizedDescription)")
        }
    }

    private func isAcceptable(_ face: VNFaceObservation) -> Bool {
        let box = face.boundingBox
        let center = CGPoint(x: box.midX, y: box.midY)
        return box.width >= 0.20 && box.height >= 0.20
            && (0.28...0.72).contains(center.x)
            && (0.25...0.78).contains(center.y)
            && face.confidence >= 0.75
    }

    private func advanceLiveness(with face: VNFaceObservation, pixelBuffer: CVPixelBuffer) {
        let yaw = face.yaw?.floatValue ?? 0
        switch currentState {
        case .centerFace:
            guard abs(yaw) < 0.12 else { centeredFrameCount = 0; return }
            centeredFrameCount += 1
            if centeredFrameCount >= 3 { publish(.turnHead) }
        case .turnHead:
            guard abs(yaw) > 0.20 else { turnedFrameCount = 0; return }
            turnedFrameCount += 1
            if turnedFrameCount >= 2 { publish(.returnToCenter) }
        case .returnToCenter:
            guard abs(yaw) < 0.10 else { returnedFrameCount = 0; return }
            returnedFrameCount += 1
            if returnedFrameCount >= 2 {
                publish(.matching)
                match(pixelBuffer: pixelBuffer)
            }
        case .matching:
            match(pixelBuffer: pixelBuffer)
        default:
            break
        }
    }

    private func match(pixelBuffer: CVPixelBuffer) {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            fail("ไม่สามารถอ่านภาพจากกล้องได้")
            return
        }
        do {
            let score = try FaceEmbeddingService.shared.similarity(of: cgImage, to: referenceEmbedding)
            similaritySamples.append(score)
            guard similaritySamples.count >= 3 else { return }
            let sorted = similaritySamples.sorted()
            let median = sorted[sorted.count / 2]
            isFinished = true
            if median >= FaceEmbeddingService.defaultMatchThreshold {
                publish(.success(median))
                stop()
            } else {
                fail("ใบหน้าไม่ตรงกับพนักงานที่เลือก กรุณาลองใหม่")
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private var currentState: State {
        DispatchQueue.main.sync { state }
    }

    private func publish(_ newState: State) {
        DispatchQueue.main.async { self.state = newState }
    }

    private func resetProgress(message: String) {
        centeredFrameCount = 0
        turnedFrameCount = 0
        returnedFrameCount = 0
        similaritySamples.removeAll(keepingCapacity: true)
        publish(.failure(message))
        captureQueue.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, !self.isFinished else { return }
            self.publish(.centerFace)
        }
    }
}
