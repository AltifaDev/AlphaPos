//
//  PrinterConnectivity.swift
//  AlphaPos — Universal Printer Connectivity & Discovery
//
//  Provides brand-agnostic connectivity primitives so that ANY printer
//  supported on iPad / iPhone can be discovered, probed, and validated:
//
//    1. TCPConnectivityProbe   — Verify a network printer is reachable at
//                                 host:port WITHOUT sending a print job.
//                                 (RAW 9100 / LPR 515 / IPP 631 aware.)
//    2. BonjourPrinterDiscovery — Auto-discover network printers advertised
//                                 over mDNS/Bonjour (_pdl-datastream._tcp,
//                                 _printer._tcp, _ipp._tcp).
//    3. USBAccessoryProbe       — Enumerate connected MFi USB accessories.
//    4. PrinterCapability       — Capability matrix per brand × interface,
//                                 the single source of truth used by the UI
//                                 to guide the user toward a working setup.
//
//  Design goal: future-proof, standards-compliant printer management that
//  degrades gracefully — every printer that iOS itself can reach becomes
//  discoverable and testable here.
//

import Foundation
import Combine
import Network
import ExternalAccessory

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Connectivity Result
// ─────────────────────────────────────────────────────────────────────────────

/// Outcome of a connectivity probe. Separate from PrintResult because a
/// reachable socket does NOT imply a successful print — it only confirms the
/// transport layer is alive.
struct ConnectivityResult: Sendable {
    enum State: String, Sendable {
        case reachable          // socket opened successfully
        case refused            // host reachable but port closed (connection refused)
        case timedOut           // no response within the deadline
        case invalidHost        // malformed IP / hostname
        case networkDown        // local network unavailable / not permitted
        case unknown
    }

    let state: State
    let latencyMs: Int?
    let detail: String

    var isReachable: Bool { state == .reachable }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TCP Connectivity Probe (no print job)
// ─────────────────────────────────────────────────────────────────────────────

/// Opens a TCP socket to host:port and immediately closes it, purely to
/// confirm reachability. This is the standards-compliant way to answer the
/// question "is the printer online?" without emitting paper.
enum TCPConnectivityProbe {

    private final class ResumeGate: @unchecked Sendable {
        private let lock = NSLock()
        nonisolated(unsafe) private var hasResumed = false

        nonisolated func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !hasResumed else { return false }
            hasResumed = true
            return true
        }
    }

    /// Probe a raw TCP endpoint (default RAW port 9100).
    /// - Returns: ConnectivityResult describing reachability + latency.
    static func probe(host: String, port: UInt16, timeout: Double = 4.0) async -> ConnectivityResult {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ConnectivityResult(state: .invalidHost, latencyMs: nil,
                                      detail: "Host is empty.")
        }

        return await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(trimmed),
                port: NWEndpoint.Port(integerLiteral: port)
            )

            // TCP with a short connection timeout — we only need the handshake.
            let params = NWParameters.tcp

            let connection = NWConnection(to: endpoint, using: params)
            let queue = DispatchQueue(label: "com.alphapos.probe.\(trimmed)")
            let start = DispatchTime.now()

            let resumeGate = ResumeGate()
            let finish: @Sendable (ConnectivityResult) -> Void = { result in
                guard resumeGate.claim() else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }

            let timeoutTimer = DispatchSource.makeTimerSource(queue: queue)
            timeoutTimer.schedule(deadline: .now() + timeout)
            timeoutTimer.setEventHandler {
                finish(ConnectivityResult(
                    state: .timedOut, latencyMs: nil,
                    detail: "No response from \(trimmed):\(port) within \(Int(timeout))s. Check the printer is powered on and on the same network."
                ))
            }
            timeoutTimer.resume()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timeoutTimer.cancel()
                    let ms = Int(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0)
                    finish(ConnectivityResult(
                        state: .reachable, latencyMs: ms,
                        detail: "Printer reachable at \(trimmed):\(port) (\(ms) ms)."
                    ))
                case .failed(let error):
                    timeoutTimer.cancel()
                    let mapped: ConnectivityResult.State
                    switch error {
                    case .posix(.ECONNREFUSED): mapped = .refused
                    case .posix(.ENETDOWN), .posix(.ENETUNREACH): mapped = .networkDown
                    case .posix(.EHOSTUNREACH), .posix(.ETIMEDOUT): mapped = .timedOut
                    default: mapped = .unknown
                    }
                    finish(ConnectivityResult(
                        state: mapped, latencyMs: nil,
                        detail: "Connection failed: \(error.localizedDescription)"
                    ))
                case .waiting(let error):
                    // "waiting" usually means local network permission or the
                    // route is not yet available. Treat persistent waiting as
                    // network-down after the timeout fires.
                    #if DEBUG
                    print("[TCPConnectivityProbe] waiting: \(error.localizedDescription)")
                    #endif
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Discovered Printer
// ─────────────────────────────────────────────────────────────────────────────

/// A network printer found via Bonjour/mDNS. `host`/`port` are resolved when
/// available so the user can add it with one tap.
struct DiscoveredPrinter: Identifiable, Sendable, Hashable {
    let id: String            // stable identity (service name + type)
    let name: String          // human-readable service name
    let serviceType: String   // e.g. _pdl-datastream._tcp
    var host: String?         // resolved IPv4/host, if available
    var port: UInt16?         // resolved port, if available

    /// Best-guess brand inferred from the advertised service name.
    var inferredBrand: PrinterBrand? {
        let lower = name.lowercased()
        if lower.contains("star")            { return .star }
        if lower.contains("epson") || lower.contains("tm-") { return .epson }
        if lower.contains("bixolon") || lower.contains("srp") { return .bixolon }
        if lower.contains("xprinter") || lower.contains("xp-") { return .xprinter }
        return nil
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Bonjour / mDNS Printer Discovery
// ─────────────────────────────────────────────────────────────────────────────

/// Discovers RAW/PDL receipt printers. IPP and LPD are intentionally excluded:
/// they require protocol framing and cannot accept a raw ESC/POS payload.
///
/// NOTE: iOS 14+ requires the app's Info.plist to declare `NSBonjourServices`
/// listing every service type below, plus `NSLocalNetworkUsageDescription`.
@MainActor
final class BonjourPrinterDiscovery: ObservableObject {

    @Published private(set) var printers: [DiscoveredPrinter] = []
    @Published private(set) var isScanning = false

    static let serviceTypes = [
        "_pdl-datastream._tcp",
    ]

    private var browsers: [NWBrowser] = []
    private var pending: [String: DiscoveredPrinter] = [:]

    /// Begin scanning. Auto-stops after `duration` seconds (default 8s) to
    /// conserve battery — restart on demand from the UI.
    func start(duration: Double = 8.0) {
        stop()
        isScanning = true
        printers = []
        pending = [:]

        for type in Self.serviceTypes {
            let params = NWParameters()
            params.includePeerToPeer = false
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: params)

            browser.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self else { return }
                Task { @MainActor in
                    self.ingest(results: results, serviceType: type)
                }
            }
            browser.stateUpdateHandler = { state in
                #if DEBUG
                print("[Bonjour] \(type) browser state: \(state)")
                #endif
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }

        // Auto-stop timer
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.stop()
        }
    }

    func stop() {
        for b in browsers { b.cancel() }
        browsers.removeAll()
        isScanning = false
    }

    private func ingest(results: Set<NWBrowser.Result>, serviceType: String) {
        for result in results {
            if case let .service(name, type, domain, _) = result.endpoint {
                let key = "\(name).\(type)\(domain)"
                if pending[key] == nil {
                    let discovered = DiscoveredPrinter(
                        id: key,
                        name: name,
                        serviceType: serviceType,
                        host: nil,
                        port: nil
                    )
                    pending[key] = discovered
                    resolve(endpoint: result.endpoint, key: key)
                }
            }
        }
        printers = Array(pending.values).sorted { $0.name < $1.name }
    }

    /// Resolve a Bonjour service endpoint to host:port via a transient
    /// NWConnection so the user gets a concrete address to save.
    private func resolve(endpoint: NWEndpoint, key: String) {
        let resolver = NWConnection(to: endpoint, using: .tcp)
        resolver.stateUpdateHandler = { [weak self, weak resolver] state in
            guard let resolver else { return }
            switch state {
            case .ready:
                if let remote = resolver.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = remote {
                    let hostStr: String
                    switch host {
                    case .ipv4(let a): hostStr = "\(a)".components(separatedBy: "%").first ?? "\(a)"
                    case .ipv6(let a): hostStr = "\(a)".components(separatedBy: "%").first ?? "\(a)"
                    case .name(let n, _): hostStr = n
                    @unknown default: hostStr = ""
                    }
                    guard let discovery = self else { return }
                    Task { @MainActor [discovery] in
                        discovery.updateResolved(key: key, host: hostStr, port: port.rawValue)
                    }
                }
                resolver.cancel()
            case .failed, .cancelled:
                resolver.cancel()
            default:
                break
            }
        }
        resolver.start(queue: .main)
    }

    private func updateResolved(key: String, host: String, port: UInt16) {
        guard var entry = pending[key] else { return }
        entry.host = host
        entry.port = port
        pending[key] = entry
        printers = Array(pending.values).sorted { $0.name < $1.name }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - USB Accessory Probe
// ─────────────────────────────────────────────────────────────────────────────

/// Thin wrapper over EAAccessoryManager to enumerate connected MFi accessories
/// and classify whether AlphaPos can drive them.
enum USBAccessoryProbe {

    struct Entry: Identifiable, Sendable {
        let id: Int              // connectionID
        let name: String
        let manufacturer: String
        let model: String
        let protocols: [String]
        let matchedBrand: PrinterBrand?
        var isSupported: Bool { matchedBrand != nil }
    }

    static func connectedAccessories() -> [Entry] {
        let supported = PrinterBrand.allCases.flatMap { brand in
            brand.mfiProtocols.map { ($0, brand) }
        }
        let map = Dictionary(supported, uniquingKeysWith: { a, _ in a })

        return EAAccessoryManager.shared().connectedAccessories.map { acc in
            let matched = acc.protocolStrings.compactMap { map[$0] }.first
            return Entry(
                id: acc.connectionID,
                name: acc.name,
                manufacturer: acc.manufacturer,
                model: acc.modelNumber,
                protocols: acc.protocolStrings,
                matchedBrand: matched
            )
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Printer Capability Matrix
// ─────────────────────────────────────────────────────────────────────────────

/// The single source of truth for "what works where" — brand × interface.
/// The settings UI consults this to steer the user toward a viable setup and
/// to show accurate, non-misleading availability badges.
enum PrinterCapability {

    enum Interface: String { case network, bluetooth, usb }

    enum Support: String {
        case supported          // works today
        case requiresMFi        // only if the specific model is MFi-certified
        case requiresSDK        // needs a vendor SDK compiled into the build
        case unsupported        // not possible on iOS/iPadOS
    }

    /// Whether a brand can print over the given interface on iOS/iPadOS.
    static func support(brand: PrinterBrand, over interface: Interface) -> Support {
        switch interface {
        case .network:
            return brand.supportsRawTCP ? .supported : .unsupported
        case .bluetooth:
            return brand.mfiProtocols.isEmpty ? .unsupported : .requiresMFi
        case .usb:
            if brand.requiresSDKForUSB { return .requiresSDK }
            if brand.supportsRawUSB { return .requiresMFi }
            // Brands with no MFi protocol cannot use USB direct on iOS.
            return brand.mfiProtocols.isEmpty ? .unsupported : .requiresMFi
        }
    }

    /// A short, user-facing explanation for the (brand, interface) pairing.
    static func advice(brand: PrinterBrand, over interface: Interface) -> String {
        switch support(brand: brand, over: interface) {
        case .supported:
            return "รองรับเต็มรูปแบบ — แนะนำให้เชื่อมต่อผ่าน \(interface == .network ? "Wi-Fi/LAN (พอร์ต 9100)" : interface.rawValue)"
        case .requiresMFi:
            return "รองรับเฉพาะรุ่นที่เป็น MFi-certified — หากรุ่นนี้ไม่ผ่าน MFi ให้ใช้ Wi-Fi/LAN แทน"
        case .requiresSDK:
            return "\(brand.displayName) USB ต้องใช้ vendor SDK — แนะนำให้ใช้ Wi-Fi/LAN (พอร์ต 9100) เพื่อความเสถียร"
        case .unsupported:
            return "\(brand.displayName) ไม่รองรับ \(interface.rawValue) บน iPad/iPhone (ข้อจำกัด Apple MFi) — กรุณาใช้ Wi-Fi/LAN"
        }
    }

    /// The recommended default interface for a brand — used to pre-select the
    /// most-likely-to-work option when the user picks a brand.
    static func recommendedInterface(for brand: PrinterBrand) -> Interface {
        // Network (RAW 9100) is universally supported and the most robust.
        return .network
    }

    /// Interfaces to present in the settings UI for a brand, ordered best-first.
    /// Interfaces that are outright impossible on iOS/iPadOS (`.unsupported`)
    /// are omitted so the operator can never pick a dead-end path — this is the
    /// core of the "make the right way the default" behaviour.
    static func selectableInterfaces(for brand: PrinterBrand) -> [Interface] {
        let ordered: [Interface] = [.network, .bluetooth, .usb]
        return ordered.filter { support(brand: brand, over: $0) != .unsupported }
    }

    /// Whether an interface is fully supported (works today with no extra
    /// caveats). Used to color/annotate the UI advice banner.
    static func isFullySupported(brand: PrinterBrand, over interface: Interface) -> Bool {
        support(brand: brand, over: interface) == .supported
    }
}
