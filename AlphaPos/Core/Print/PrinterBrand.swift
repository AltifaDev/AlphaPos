import Foundation

enum PrinterBrand: String, CaseIterable, Identifiable, Codable {
    case epson = "epson"
    case star = "star"
    case xprinter = "xprinter"
    case generic = "generic"
    case tspl = "tspl"
    case bixolon = "bixolon"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .epson: return "Epson"
        case .star: return "Star Micronics"
        case .xprinter: return "Xprinter"
        case .generic: return "Generic / Custom"
        case .tspl: return "TSC Label"
        case .bixolon: return "Bixolon"
        }
    }

    var defaultCommandSet: PrintCommandSet {
        switch self {
        case .star:
            return .starPRNT
        case .tspl:
            return .tspl
        case .epson, .xprinter, .generic, .bixolon:
            return .escpos
        }
    }

    var supportsRawTCP: Bool {
        switch self {
        case .epson, .xprinter, .generic, .bixolon, .tspl, .star:
            return true
        }
    }

    var supportsRawUSB: Bool {
        false
    }

    var requiresSDKForUSB: Bool {
        switch self {
        case .star:
            return true
        case .epson, .xprinter, .generic, .tspl, .bixolon:
            return false
        }
    }

    var supportsDirectUSBOnIOS: Bool {
        supportsRawUSB || requiresSDKForUSB
    }

    var connectionHint: String {
        switch self {
        case .epson:
            return "Epson ESC/POS is supported over Wi-Fi/LAN using TCP/IP."
        case .star:
            return "Star USB on iPad requires the Star Micronics SDK path; TCP/IP can still use raw printing when the model supports it."
        case .xprinter:
            return "Most Xprinter models are ESC/POS-compatible over LAN/Wi‑Fi or Bluetooth bridge. Direct USB on iPad is usually unavailable unless the model is MFi-certified."
        case .generic:
            return "Generic ESC/POS printers are supported over TCP/IP. Direct USB on iPad is usually blocked unless the accessory is MFi-certified."
        case .tspl:
            return "TSPL is for label printers and is normally used over TCP/IP or vendor-specific interfaces."
        case .bixolon:
            return "Bixolon ESC/POS-compatible models are supported over Wi-Fi/LAN using TCP/IP."
        }
    }
    
    // MFi protocol strings registered with Apple
    var mfiProtocols: [String] {
        switch self {
        // Official StarXpand protocol for USB and classic Bluetooth.
        case .star: return ["jp.star-m.starpro"]
        default: return []
        }
    }
    
    // Brand-specific paper cut commands
    var cutCommand: [UInt8] {
        switch self {
        case .star:
            // Star mode: ESC d n cuts paper. n=3 = partial cut after feeding to cut position.
            // (The previous value 0x32 = 50 fed 50 lines instead of cutting.)
            return [0x1B, 0x64, 0x03] // Star partial cut
        default:
            return [0x1D, 0x56, 0x42, 0x00] // Epson/Generic full cut
        }
    }
}
