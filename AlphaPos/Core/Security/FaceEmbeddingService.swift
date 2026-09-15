import CoreML
import Vision
import CoreGraphics

/// On-device face embedding service. This model is independent of Apple Face ID.
/// It receives a tightly cropped face and returns a normalized 256-value vector.
final class FaceEmbeddingService {
    static let shared = FaceEmbeddingService()

    /// Conservative starting point for the bundled model. This must be
    /// recalibrated with representative staff images before changing it.
    static let defaultMatchThreshold: Float = 0.72

    enum Error: LocalizedError {
        case modelUnavailable
        case noFace
        case multipleFaces
        case poorCaptureQuality
        case invalidOutput

        var errorDescription: String? {
            switch self {
            case .modelUnavailable: return "ไม่พบโมเดลตรวจสอบใบหน้าในแอป"
            case .noFace: return "ไม่พบใบหน้า กรุณาจัดใบหน้าให้อยู่ในกรอบ"
            case .multipleFaces: return "พบมากกว่าหนึ่งใบหน้า กรุณาให้มีเพียงพนักงานหนึ่งคนในกรอบ"
            case .poorCaptureQuality: return "ภาพใบหน้าไม่ชัดเจน กรุณามองตรง เพิ่มแสง และถ่ายใหม่"
            case .invalidOutput: return "โมเดลไม่สามารถสร้างข้อมูลใบหน้าได้"
            }
        }
    }

    private let model: MLModel?

    private init() {
        guard let url = Bundle.main.url(forResource: "FaceEmbedding", withExtension: "mlmodelc") else {
            model = nil
            return
        }
        model = try? MLModel(contentsOf: url)
    }

    func embedding(from image: CGImage) throws -> [Float] {
        guard let model else { throw Error.modelUnavailable }
        let face = try detectFace(in: image)
        try validateCaptureQuality(in: image, detectedFace: face)
        let crop = try crop(image, to: face.boundingBox)
        let input = try makeInput(from: crop)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["input": input])
        let result = try model.prediction(from: provider)
        guard let array = result.featureValue(for: "embedding")?.multiArrayValue
                ?? result.featureValue(for: "output")?.multiArrayValue else {
            throw Error.invalidOutput
        }
        let values = (0..<array.count).map { array[$0].floatValue }
        guard !values.isEmpty else { throw Error.invalidOutput }
        return Self.normalize(values)
    }

    func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        let dot = zip(lhs, rhs).reduce(Float.zero) { $0 + $1.0 * $1.1 }
        let left = sqrt(zip(lhs, lhs).reduce(Float.zero) { $0 + $1.0 * $1.1 })
        let right = sqrt(zip(rhs, rhs).reduce(Float.zero) { $0 + $1.0 * $1.1 })
        guard left > 0, right > 0 else { return 0 }
        return dot / (left * right)
    }

    func decodeEmbedding(_ data: Data) throws -> [Float] {
        guard !data.isEmpty,
              data.count.isMultiple(of: MemoryLayout<Float>.stride) else {
            throw Error.invalidOutput
        }
        let values = data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else {
            throw Error.invalidOutput
        }
        return Self.normalize(values)
    }

    func similarity(of image: CGImage, to storedEmbedding: Data) throws -> Float {
        let reference = try decodeEmbedding(storedEmbedding)
        let candidate = try embedding(from: image)
        return cosineSimilarity(reference, candidate)
    }

    private func detectFace(in image: CGImage) throws -> VNFaceObservation {
        let request = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let faces = request.results ?? []
        guard faces.count == 1, let face = faces.first else {
            throw faces.isEmpty ? Error.noFace : Error.multipleFaces
        }
        return face
    }

    private func validateCaptureQuality(in image: CGImage, detectedFace: VNFaceObservation) throws {
        guard detectedFace.boundingBox.width >= 0.18,
              detectedFace.boundingBox.height >= 0.18,
              detectedFace.confidence >= 0.75 else {
            throw Error.poorCaptureQuality
        }

        let request = VNDetectFaceCaptureQualityRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let observation = request.results?.first,
              request.results?.count == 1,
              let quality = observation.faceCaptureQuality,
              quality >= 0.35 else {
            throw Error.poorCaptureQuality
        }
    }

    private func crop(_ image: CGImage, to rect: CGRect) throws -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let pixelRect = CGRect(
            x: rect.minX * width,
            y: (1 - rect.maxY) * height,
            width: rect.width * width,
            height: rect.height * height
        ).insetBy(dx: -rect.width * width * 0.20, dy: -rect.height * height * 0.20)
        guard let result = image.cropping(to: pixelRect.intersection(CGRect(x: 0, y: 0, width: width, height: height))) else {
            throw Error.noFace
        }
        return result
    }

    private func makeInput(from image: CGImage) throws -> MLMultiArray {
        let input = try MLMultiArray(shape: [1, 3, 128, 128], dataType: .float32)
        guard let context = CGContext(
            data: nil, width: 128, height: 128, bitsPerComponent: 8,
            bytesPerRow: 128 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw Error.invalidOutput }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: 128, height: 128))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { throw Error.invalidOutput }
        for y in 0..<128 {
            for x in 0..<128 {
                let pixel = (y * 128 + x) * 4
                let r = Float(data[pixel])
                let g = Float(data[pixel + 1])
                let b = Float(data[pixel + 2])
                input[y * 128 + x] = NSNumber(value: b)
                input[128 * 128 + y * 128 + x] = NSNumber(value: g)
                input[2 * 128 * 128 + y * 128 + x] = NSNumber(value: r)
            }
        }
        return input
    }

    private static func normalize(_ values: [Float]) -> [Float] {
        let norm = sqrt(values.reduce(Float.zero) { $0 + $1 * $1 })
        return norm > 0 ? values.map { $0 / norm } : values
    }
}
