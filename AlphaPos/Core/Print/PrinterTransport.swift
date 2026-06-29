import Foundation
import Network
import ExternalAccessory
#if canImport(CoreImage)
import CoreImage
#endif
#if canImport(StarIO10)
import StarIO10
#endif
#if canImport(UIKit)
import UIKit
#endif

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TCP Transport (Network Port 9100)
// ─────────────────────────────────────────────────────────────────────────────
struct TCPTransport: PrinterTransport {
    let timeout: Double
    
    init(timeout: Double = 5.0) {
        self.timeout = timeout
    }
    
    func deliver(data: Data, printer: Printer, logger: PrintLogger) async -> PrintResult {
        guard let ip = printer.ipAddress, !ip.isEmpty else {
            logger.append("    ERROR: IP address is empty.")
            return PrintResult(success: false, message: "TCP/IP connection requires a valid IP address.")
        }
        
        logger.append("    Connecting to TCP/IP raw socket \(ip):\(printer.port)...")
        logger.append("    Initializing NWConnection socket...")
        
        let result = await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(ip),
                port: NWEndpoint.Port(integerLiteral: UInt16(printer.port))
            )
            let connection = NWConnection(to: endpoint, using: .tcp)
            let queue = DispatchQueue(label: "com.alphapos.print.\(ip)")
            
            var didResume = false
            let resume = { (success: Bool, message: String) in
                if !didResume {
                    didResume = true
                    connection.cancel()
                    continuation.resume(returning: PrintResult(success: success, message: message))
                }
            }
            
            let timeoutTimer = DispatchSource.makeTimerSource(queue: queue)
            timeoutTimer.schedule(deadline: .now() + timeout)
            timeoutTimer.setEventHandler {
                resume(false, "Connection timed out to \(ip):\(printer.port) after \(Int(timeout)) seconds. Check network or printer status.")
            }
            timeoutTimer.resume()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    logger.append("    Socket connected. Sending data...")
                    connection.send(content: data, completion: .contentProcessed { error in
                        timeoutTimer.cancel()
                        if let error = error {
                            resume(false, "Transmission error: \(error.localizedDescription)")
                        } else {
                            resume(true, "Data sent successfully.")
                        }
                    })
                case .failed(let error):
                    timeoutTimer.cancel()
                    resume(false, "Network connection failed: \(error.localizedDescription)")
                case .waiting(let error):
                    #if DEBUG
                    print("TCP connecting to \(ip) waiting: \(error.localizedDescription)")
                    #endif
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
        return result
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EAAccessory Transport (USB MFi Fallback)
// ─────────────────────────────────────────────────────────────────────────────
struct EAAccessoryTransport: PrinterTransport {
    func deliver(data: Data, printer: Printer, logger: PrintLogger) async -> PrintResult {
        let supportedProtocols = PrinterBrand.allCases.flatMap { $0.mfiProtocols }
        
        if let configuredBrand = PrinterBrand(rawValue: printer.emulation) {
            logger.append("    Configured brand: \(configuredBrand.displayName)")
            logger.append("    Brand hint: \(configuredBrand.connectionHint)")

            if configuredBrand.requiresSDKForUSB {
                logger.append("    ERROR: \(configuredBrand.displayName) USB requires its vendor SDK transport.")
                return PrintResult(
                    success: false,
                    message: "\(configuredBrand.displayName) USB on iPad requires its vendor SDK. Use TCP/IP for now, or link the vendor SDK."
                )
            }

            if !configuredBrand.supportsDirectUSBOnIOS && configuredBrand.mfiProtocols.isEmpty {
                logger.append("    \(configuredBrand.displayName) has no registered MFi USB protocol in this build.")
                return PrintResult(
                    success: false,
                    message: "\(configuredBrand.displayName) direct USB is not available on iPad unless the printer is MFi-certified. Use TCP/IP LAN/Wi‑Fi for ESC/POS printing."
                )
            }
        }
        
        logger.append("    Accessing EAAccessoryManager...")
        let manager = EAAccessoryManager.shared()
        let accessories = manager.connectedAccessories
        logger.append("    Found \(accessories.count) MFi accessory/accessories connected.")
        
        guard let accessory = accessories.first(where: { acc in
            acc.protocolStrings.contains(where: { supportedProtocols.contains($0) })
        }) else {
            logger.append("    ERROR: No connected MFi accessory matches registered brand protocols.")
            return PrintResult(success: false, message: "No connected MFi USB/Lightning accessory found. Please check cable connection and make sure the printer is turned on.")
        }
        
        let detectedBrand = PrinterBrand.allCases.first(where: { brand in
            accessory.protocolStrings.contains(where: { brand.mfiProtocols.contains($0) })
        })
        
        logger.append("    Accessory found: \(accessory.name)")
        logger.append("    Manufacturer: \(accessory.manufacturer)")
        logger.append("    Model: \(accessory.modelNumber)")
        if let brand = detectedBrand {
            logger.append("    System detected brand: \(brand.displayName)")
        }
        
        let accessoryProtocols = accessory.protocolStrings.filter { supportedProtocols.contains($0) }
        
        guard !accessoryProtocols.isEmpty else {
            logger.append("    ERROR: No supported protocol string found on accessory.")
            return PrintResult(success: false, message: "No supported protocol string found on the accessory.")
        }
        
        logger.append("    Supported protocols matching this brand: \(accessoryProtocols.joined(separator: ", "))")
        
        var session: EASession? = nil
        var chosenProtocol: String? = nil
        
        for protocolString in accessoryProtocols {
            logger.append("    Attempting to open EASession with protocol: \(protocolString)...")
            for retry in 1...3 {
                session = EASession(accessory: accessory, forProtocol: protocolString)
                if session != nil {
                    chosenProtocol = protocolString
                    break
                }
                logger.append("        WARNING: EASession returned nil (attempt \(retry)/3), retrying in 250ms...")
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            if session != nil {
                break
            }
        }
        
        guard let activeSession = session, let protocolString = chosenProtocol else {
            logger.append("    ERROR: Failed to establish EASession with any supported protocol.")
            return PrintResult(
                success: false,
                message: "Failed to establish a communication session with \(accessory.name) (Session Busy). Please make sure no other printer utility apps are open in the background, unplug and reconnect the cable, and try again."
            )
        }
        
        logger.append("    Successfully established EASession with protocol: \(protocolString)")
        
        guard let outputStream = activeSession.outputStream else {
            logger.append("    ERROR: EASession outputStream is nil.")
            return PrintResult(success: false, message: "Could not open output channel to \(accessory.name).")
        }
        
        logger.append("    Scheduling Output Stream in Main RunLoop...")
        let streamRunLoop = RunLoop.current
        outputStream.schedule(in: streamRunLoop, forMode: .default)
        
        logger.append("    Opening Output Stream...")
        outputStream.open()
        defer {
            logger.append("    Closing Output Stream...")
            outputStream.close()
            outputStream.remove(from: streamRunLoop, forMode: .default)
        }
        
        logger.append("    Waiting for stream space availability...")
        var spaceReady = false
        for _ in 0..<40 {
            if outputStream.hasSpaceAvailable {
                spaceReady = true
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        
        if !spaceReady {
            logger.append("    WARNING: Stream did not signal space availability, attempting write anyway...")
        }
        
        var bytesWritten = 0
        let dataSize = data.count
        let buffer = Array(data)
        
        var remaining = dataSize
        var offset = 0
        var zeroWriteRetries = 0
        
        logger.append("    Writing payload to accessory stream...")
        while remaining > 0 {
            if Task.isCancelled {
                logger.append("    ERROR: Write cancelled.")
                return PrintResult(success: false, message: "Write operation cancelled.")
            }
            
            let written = buffer.withUnsafeBufferPointer { bufPtr in
                outputStream.write(bufPtr.baseAddress! + offset, maxLength: remaining)
            }
            if written < 0 {
                logger.append("    ERROR: Write failure: \(outputStream.streamError?.localizedDescription ?? "unknown error")")
                return PrintResult(success: false, message: "Failed to write data to USB stream: \(outputStream.streamError?.localizedDescription ?? "unknown error")")
            } else if written == 0 {
                zeroWriteRetries += 1
                if zeroWriteRetries > 60 {
                    logger.append("    ERROR: Write timeout (stream buffer is full/offline).")
                    return PrintResult(success: false, message: "Write timeout: The printer is connected but not accepting data. Please make sure the printer is turned on, has paper, and is not offline.")
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            zeroWriteRetries = 0
            bytesWritten += written
            remaining -= written
            offset += written
        }
        
        logger.append("    Successfully wrote \(bytesWritten) bytes.")
        return PrintResult(success: true, message: "Printed successfully via USB/Lightning to \(accessory.name).")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Star SDK Transport (Official Star SDK Placeholder Stub)
// ─────────────────────────────────────────────────────────────────────────────
struct StarUSBTransport: PrinterTransport {
    func deliver(data: Data, printer: Printer, logger: PrintLogger) async -> PrintResult {
        logger.append("    Routing to official Star Micronics SDK Command Path...")
        logger.append("    Searching for USB accessory matching Star Micronics protocols...")
        
#if canImport(StarIO10) && canImport(UIKit)
        let settings = StarConnectionSettings(
            interfaceType: .usb,
            identifier: StarConnectionSettings.FIRST_FOUND_DEVICE,
            autoSwitchInterface: false
        )
        let starPrinter = StarPrinter(settings)

        do {
            try await starPrinter.open()
            defer {
                Task { await starPrinter.close() }
            }

            let printableWidth = printer.paperWidth == "58mm" ? 384 : 576
            let image = await MainActor.run {
                receiptImage(from: data, width: printableWidth)
            }
            let imageParameter = StarXpandCommand.Printer.ImageParameter(image: image, width: printableWidth)
                .setEffectDiffusion(true)

            let builder = StarXpandCommand.StarXpandCommandBuilder()
            _ = builder.addDocument(
                StarXpandCommand.DocumentBuilder()
                    .addPrinter(
                        StarXpandCommand.PrinterBuilder()
                            .actionPrintImage(imageParameter)
                            .actionFeedLine(3)
                            .actionCut(StarXpandCommand.Printer.CutType.partial)
                    )
            )

            try await starPrinter.print(command: builder.getCommands())
            logger.append("    Star SDK print completed.")
            return PrintResult(success: true, message: "Printed successfully via Star Micronics USB SDK.")
        } catch {
            logger.append("    ERROR: Star SDK print failed: \(error.localizedDescription)")
            return PrintResult(success: false, message: "Star USB print failed: \(error.localizedDescription)")
        }
#else
        // ponytail: no raw EASession fallback for Star; add the SDK adapter when the framework is linked.
        logger.append("    Star SDK is not compiled in this build target.")
        return PrintResult(
            success: false,
            message: "Star TSP143IIIU USB is detected, but this build does not include the Star Micronics SDK. Use TCP/IP for now, or link StarXpand/StarPRNT SDK."
        )
#endif
    }

    private func bestEffortText(from data: Data) -> String {
        let decoded = String(data: stripEscPosCommands(from: data), encoding: .windowsCP874)
            ?? String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
        return decoded
            .replacingOccurrences(of: "\u{1B}", with: "")
            .replacingOccurrences(of: "\u{1D}", with: "")
            .filter { $0 == "\n" || $0 == "\r" || !$0.isASCII || ($0.asciiValue.map { $0 >= 0x20 && $0 < 0x7F } ?? false) }
    }

#if canImport(UIKit)
    @MainActor
    private func receiptImage(from data: Data, width: Int) -> UIImage {
        // Parse ESC/POS bytes into a list of typed segments, then render each
        // in a two-pass layout (measure height → draw) preserving alignment,
        // bold, double-size, logo raster images, and QR code bitmaps.
        let segments = parseEscPosSegments(data, paperWidthDots: width)
        return renderSegments(segments, paperWidthDots: width)
    }
#endif

    // ── ESC/POS segment model ─────────────────────────────────────────────────
    private enum Alignment { case left, center, right }
    private struct TextLine {
        var text: String
        var alignment: Alignment
        var bold: Bool
        var doubleSize: Bool
    }
    private enum PrintSegment {
        case line(TextLine)
        case rasterLogo(UIImage)  // from GS v 0 bitmap embedded in data
        case qrPlaceholder(String) // QR payload string — rendered as CIQRCodeGenerator
    }

    // ── Parser ────────────────────────────────────────────────────────────────
    private func parseEscPosSegments(_ data: Data, paperWidthDots: Int) -> [PrintSegment] {
        let bytes = [UInt8](data)
        var segments: [PrintSegment] = []
        var currentLine = ""
        var align: Alignment = .left
        var bold = false
        var doubleSize = false
        var i = 0

        func flushLine() {
            segments.append(.line(TextLine(text: currentLine, alignment: align, bold: bold, doubleSize: doubleSize)))
            currentLine = ""
        }

        while i < bytes.count {
            let b = bytes[i]
            if b == 0x0A {          // LF — new line
                flushLine()
                i += 1
            } else if b == 0x0D {   // CR — ignore
                i += 1
            } else if b == 0x1B {   // ESC sequence
                guard i + 1 < bytes.count else { i += 1; continue }
                switch bytes[i + 1] {
                case 0x40:           // ESC @ (init)
                    align = .left; bold = false; doubleSize = false; i += 2
                case 0x61:           // ESC a n (alignment)
                    if i + 2 < bytes.count {
                        switch bytes[i + 2] {
                        case 0x00: align = .left
                        case 0x01: align = .center
                        case 0x02: align = .right
                        default: break
                        }
                        i += 3
                    } else { i += 2 }
                case 0x45:           // ESC E n (bold)
                    if i + 2 < bytes.count { bold = bytes[i + 2] != 0x00; i += 3 } else { i += 2 }
                case 0x21:           // ESC ! n (char size)
                    if i + 2 < bytes.count {
                        let n = bytes[i + 2]
                        doubleSize = (n & 0x30) != 0  // bit 4 or 5 = double height/width
                        i += 3
                    } else { i += 2 }
                case 0x64:           // ESC d n (feed n lines)
                    let n = i + 2 < bytes.count ? Int(bytes[i + 2]) : 1
                    for _ in 0..<n { flushLine() }
                    i += 3
                default:             // other ESC — skip 2–3 bytes
                    i += min(3, bytes.count - i)
                }
            } else if b == 0x1D {   // GS sequence
                guard i + 1 < bytes.count else { i += 1; continue }
                if bytes[i + 1] == 0x76 && i + 7 < bytes.count {
                    // GS v 0 — raster image
                    // mode=bytes[i+3], xL=bytes[i+4], xH=bytes[i+5], yL=bytes[i+6], yH=bytes[i+7]
                    let xL = Int(bytes[i + 4]); let xH = Int(bytes[i + 5])
                    let yL = Int(bytes[i + 6]); let yH = Int(bytes[i + 7])
                    let bytesPerRow = xL + xH * 256
                    let numRows     = yL + yH * 256
                    let dataLen     = bytesPerRow * numRows
                    let dataStart   = i + 8
                    if dataStart + dataLen <= bytes.count, bytesPerRow > 0, numRows > 0 {
                        let bmp = Data(bytes[dataStart..<dataStart + dataLen])
                        if let img = bitmap1BitToUIImage(bmp, bytesPerRow: bytesPerRow, height: numRows) {
                            flushLine()
                            segments.append(.rasterLogo(img))
                        }
                    }
                    i += 8 + dataLen
                } else if bytes[i + 1] == 0x28 && i + 4 < bytes.count {
                    // GS ( L — QR code or other 2D
                    let length = Int(bytes[i + 3]) + Int(bytes[i + 4]) * 256
                    // Store QR payload if this is the data function (pL pH m fn [data])
                    // fn == 0x50 (store symbol data)
                    if i + 6 < bytes.count && bytes[i + 5] == 0x31 && bytes[i + 6] == 0x50 {
                        let payloadStart = i + 8   // skip GS ( L pL pH 0x31 0x50 0x30
                        let payloadLen   = length - 3
                        if payloadStart + payloadLen <= bytes.count {
                            let payloadData = Data(bytes[payloadStart..<payloadStart + payloadLen])
                            if let payloadStr = String(data: payloadData, encoding: .utf8) {
                                flushLine()
                                segments.append(.qrPlaceholder(payloadStr))
                            }
                        }
                    }
                    i += 5 + length
                } else if bytes[i + 1] == 0x56 {  // GS V — cut
                    i += min(4, bytes.count - i)
                } else {
                    i += min(3, bytes.count - i)
                }
            } else if b >= 0x20 {
                // Printable byte — append to current line (CP874)
                let char = String(data: Data([b]), encoding: .windowsCP874) ?? "?"
                currentLine += char
                i += 1
            } else {
                i += 1
            }
        }
        if !currentLine.isEmpty { flushLine() }
        return segments
    }

    // ── Renderer ──────────────────────────────────────────────────────────────
    @MainActor
    private func renderSegments(_ segments: [PrintSegment], paperWidthDots: Int) -> UIImage {
        let inset: CGFloat = 8
        let drawWidth = CGFloat(paperWidthDots) - inset * 2
        let fontSize: CGFloat = paperWidthDots == 384 ? 18 : 21
        let lineH: CGFloat = fontSize * 1.35
        var totalH: CGFloat = 16   // top padding

        // First pass — measure height
        for seg in segments {
            switch seg {
            case .line(let tl):
                let font = UIFont.monospacedSystemFont(ofSize: tl.doubleSize ? fontSize * 1.8 : fontSize,
                                                       weight: tl.bold ? .bold : .regular)
                let h = ceil((tl.text as NSString).boundingRect(
                    with: CGSize(width: drawWidth, height: 10000),
                    options: [.usesLineFragmentOrigin],
                    attributes: [.font: font],
                    context: nil
                ).height)
                totalH += max(h, tl.doubleSize ? lineH * 1.8 : lineH)
            case .rasterLogo(let img):
                let scale = min(1.0, drawWidth / img.size.width)
                totalH += img.size.height * scale + 8
            case .qrPlaceholder:
                totalH += 130   // 120px QR + padding
            }
        }
        totalH += 24  // bottom padding

        // Second pass — draw
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: CGFloat(paperWidthDots), height: totalH), format: format)
            .image { _ in
                UIColor.white.setFill()
                UIRectFill(CGRect(x: 0, y: 0, width: CGFloat(paperWidthDots), height: totalH))
                var y: CGFloat = 16
                for seg in segments {
                    switch seg {
                    case .line(let tl):
                        let font = UIFont.monospacedSystemFont(ofSize: tl.doubleSize ? fontSize * 1.8 : fontSize,
                                                               weight: tl.bold ? .bold : .regular)
                        let para = NSMutableParagraphStyle()
                        para.alignment = tl.alignment == .center ? .center
                                       : tl.alignment == .right  ? .right : .left
                        para.lineBreakMode = .byClipping
                        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: para]
                        let h = ceil((tl.text as NSString).boundingRect(
                            with: CGSize(width: drawWidth, height: 10000),
                            options: [.usesLineFragmentOrigin],
                            attributes: attrs, context: nil).height)
                        let lineHeight = max(h, tl.doubleSize ? lineH * 1.8 : lineH)
                        (tl.text as NSString).draw(
                            with: CGRect(x: inset, y: y, width: drawWidth, height: lineHeight),
                            options: [.usesLineFragmentOrigin],
                            attributes: attrs, context: nil)
                        y += lineHeight
                    case .rasterLogo(let img):
                        let scale = min(1.0, drawWidth / img.size.width)
                        let w = img.size.width * scale
                        let h = img.size.height * scale
                        let x = (CGFloat(paperWidthDots) - w) / 2  // center logo
                        img.draw(in: CGRect(x: x, y: y, width: w, height: h))
                        y += h + 8
                    case .qrPlaceholder(let payload):
                        if let qrImg = generateQRImage(payload, size: 120) {
                            let x = (CGFloat(paperWidthDots) - 120) / 2
                            qrImg.draw(in: CGRect(x: x, y: y, width: 120, height: 120))
                        }
                        y += 130
                    }
                }
            }
    }

    // ── 1-bit bitmap → UIImage ────────────────────────────────────────────────
    private func bitmap1BitToUIImage(_ data: Data, bytesPerRow: Int, height: Int) -> UIImage? {
        let width = bytesPerRow * 8
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            for col in 0..<(bytesPerRow * 8) {
                let byteIdx = row * bytesPerRow + col / 8
                let bit = (data[byteIdx] >> (7 - (col % 8))) & 1
                if bit == 1 {
                    let px = (row * width + col) * 4
                    rgba[px] = 0; rgba[px+1] = 0; rgba[px+2] = 0
                }
            }
        }
        let bitmapData = Data(rgba)
        guard let provider = CGDataProvider(data: bitmapData as CFData),
              let cgImg = CGImage(width: width, height: height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cgImg)
    }

    // ── QR Code generator ─────────────────────────────────────────────────────
    private func generateQRImage(_ payload: String, size: CGFloat) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(payload.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImg = filter.outputImage else { return nil }
        let scale = size / ciImg.extent.width
        let scaledImg = ciImg.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return UIImage(ciImage: scaledImg)
    }

    private func stripEscPosCommands(from data: Data) -> Data {
        let bytes = [UInt8](data)
        var output: [UInt8] = []
        var i = 0

        while i < bytes.count {
            switch bytes[i] {
            case 0x1B:
                i += skipEscCommand(bytes, at: i)
            case 0x1D:
                i += skipGsCommand(bytes, at: i)
            case 0x0A, 0x0D, 0x20...0xFF:
                output.append(bytes[i])
                i += 1
            default:
                i += 1
            }
        }

        return Data(output)
    }

    private func skipEscCommand(_ bytes: [UInt8], at index: Int) -> Int {
        guard index + 1 < bytes.count else { return 1 }
        switch bytes[index + 1] {
        case 0x40, 0x32:
            return 2
        default:
            return min(3, bytes.count - index)
        }
    }

    private func skipGsCommand(_ bytes: [UInt8], at index: Int) -> Int {
        guard index + 1 < bytes.count else { return 1 }
        if bytes[index + 1] == 0x28, index + 4 < bytes.count {
            let length = Int(bytes[index + 3]) + (Int(bytes[index + 4]) * 256)
            return min(5 + length, bytes.count - index)
        }
        return min(3, bytes.count - index)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - BLE Transport (Bluetooth Low Energy)
// ─────────────────────────────────────────────────────────────────────────────
struct BLETransport: PrinterTransport {
    func deliver(data: Data, printer: Printer, logger: PrintLogger) async -> PrintResult {
        return await BLEPrinterManager.shared.printData(data, printer: printer, logger: logger)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - BLE Printer Manager
// ─────────────────────────────────────────────────────────────────────────────
import CoreBluetooth

final class BLEPrinterManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    static let shared = BLEPrinterManager()
    
    private var centralManager: CBCentralManager?
    private var scanContinuation: CheckedContinuation<CBPeripheral, Error>?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var discoverContinuation: CheckedContinuation<CBCharacteristic, Error>?
    
    private var targetPeripheral: CBPeripheral?
    private var targetCharacteristic: CBCharacteristic?
    private var printerName: String = ""
    private var logger: PrintLogger?
    
    private override init() {
        super.init()
    }
    
    func printData(_ data: Data, printer: Printer, logger: PrintLogger) async -> PrintResult {
        self.logger = logger
        guard let name = printer.bluetoothName, !name.isEmpty else {
            logger.append("    ERROR: Bluetooth printer name is empty.")
            return PrintResult(success: false, message: "Bluetooth printing requires a configured Bluetooth Device Name.")
        }
        self.printerName = name
        
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        guard centralManager?.state == .poweredOn else {
            logger.append("    ERROR: Bluetooth is disabled or unauthorized (state: \(String(describing: centralManager?.state.rawValue)))")
            return PrintResult(success: false, message: "Please enable Bluetooth in iPad Settings to connect to wireless printers.")
        }
        
        do {
            logger.append("    Scanning for Bluetooth printer named: '\(name)'...")
            let peripheral = try await scanForPrinter()
            
            logger.append("    Connecting to \(peripheral.name ?? "BLE Device")...")
            try await connect(to: peripheral)
            
            logger.append("    Discovering services & characteristics...")
            let characteristic = try await discoverCharacteristic(on: peripheral)
            
            logger.append("    Sending payload via BLE...")
            try await writeData(data, to: characteristic, on: peripheral)
            
            centralManager?.cancelPeripheralConnection(peripheral)
            logger.append("✓ Bluetooth BLE print job completed.")
            return PrintResult(success: true, message: "Printed successfully via Bluetooth BLE to \(name).")
        } catch {
            logger.append("    ERROR: Bluetooth error: \(error.localizedDescription)")
            if let p = targetPeripheral {
                centralManager?.cancelPeripheralConnection(p)
            }
            return PrintResult(success: false, message: "Bluetooth print failed: \(error.localizedDescription)")
        }
    }
    
    private func scanForPrinter() async throws -> CBPeripheral {
        return try await withCheckedThrowingContinuation { continuation in
            self.scanContinuation = continuation
            centralManager?.scanForPeripherals(withServices: nil, options: nil)
            
            Task {
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                if self.scanContinuation != nil {
                    self.centralManager?.stopScan()
                    self.scanContinuation?.resume(throwing: NSError(domain: "BLEPrinter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Search timed out. Device '\(self.printerName)' not found. Make sure it is turned on and in range."]))
                    self.scanContinuation = nil
                }
            }
        }
    }
    
    private func connect(to peripheral: CBPeripheral) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.connectContinuation = continuation
            self.targetPeripheral = peripheral
            peripheral.delegate = self
            centralManager?.stopScan()
            centralManager?.connect(peripheral, options: nil)
            
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if self.connectContinuation != nil {
                    self.centralManager?.cancelPeripheralConnection(peripheral)
                    self.connectContinuation?.resume(throwing: NSError(domain: "BLEPrinter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to printer in a timely manner."]))
                    self.connectContinuation = nil
                }
            }
        }
    }
    
    private func discoverCharacteristic(on peripheral: CBPeripheral) async throws -> CBCharacteristic {
        return try await withCheckedThrowingContinuation { continuation in
            self.discoverContinuation = continuation
            peripheral.discoverServices(nil)
            
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if self.discoverContinuation != nil {
                    self.discoverContinuation?.resume(throwing: NSError(domain: "BLEPrinter", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to discover printer command characteristics."]))
                    self.discoverContinuation = nil
                }
            }
        }
    }
    
    private func writeData(_ data: Data, to characteristic: CBCharacteristic, on peripheral: CBPeripheral) async throws {
        let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
        let chunkLimit = min(mtu, 128)
        logger?.append("    Bluetooth MTU is \(mtu) bytes. Using write chunk limit of \(chunkLimit) bytes.")
        
        var offset = 0
        let dataSize = data.count
        let buffer = Array(data)
        
        while offset < dataSize {
            let writeSize = min(chunkLimit, dataSize - offset)
            let chunk = Data(buffer[offset..<(offset + writeSize)])
            
            peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
            offset += writeSize
            
            try? await Task.sleep(nanoseconds: 35_000_000)
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        #if DEBUG
        print("BLE central state updated: \(central.state.rawValue)")
        #endif
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? ""
        if name.lowercased().contains(printerName.lowercased()) || peripheral.identifier.uuidString == printerName {
            central.stopScan()
            scanContinuation?.resume(returning: peripheral)
            scanContinuation = nil
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectContinuation?.resume()
        connectContinuation = nil
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectContinuation?.resume(throwing: error ?? NSError(domain: "BLEPrinter", code: 4, userInfo: [NSLocalizedDescriptionKey: "Connection failed"]))
        connectContinuation = nil
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            discoverContinuation?.resume(throwing: error)
            discoverContinuation = nil
            return
        }
        
        guard let services = peripheral.services, !services.isEmpty else {
            discoverContinuation?.resume(throwing: NSError(domain: "BLEPrinter", code: 5, userInfo: [NSLocalizedDescriptionKey: "No services found on printer."]))
            discoverContinuation = nil
            return
        }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            discoverContinuation?.resume(throwing: error)
            discoverContinuation = nil
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for char in characteristics {
            if char.properties.contains(.writeWithoutResponse) || char.properties.contains(.write) {
                targetCharacteristic = char
                discoverContinuation?.resume(returning: char)
                discoverContinuation = nil
                return
            }
        }
    }
}
