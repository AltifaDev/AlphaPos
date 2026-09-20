import AudioToolbox
import AVFoundation
import Foundation

/// UI click feedback backed exclusively by iOS system sounds.
enum StaffSoundFeedback {
    static let enabledKey = "staff_sound_feedback_enabled"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    private static var paymentPlayer: AVAudioPlayer?

    static func play(_ sound: SystemSoundID = 1104) {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(sound)
    }

    /// Plays the dedicated cash-register sound after a payment is completed.
    /// Other staff UI feedback continues to use the system sounds above.
    static func paymentSuccess() {
        guard isEnabled else { return }
        if paymentPlayer == nil,
           let url = Bundle.main.url(forResource: "cash_register", withExtension: "wav") {
            paymentPlayer = try? AVAudioPlayer(contentsOf: url)
            paymentPlayer?.prepareToPlay()
        }
        paymentPlayer?.currentTime = 0
        if paymentPlayer?.play() != true {
            // Keep payment feedback audible if the bundled asset cannot be loaded.
            AudioServicesPlaySystemSound(1057)
        }
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if enabled { play() }
    }
}
