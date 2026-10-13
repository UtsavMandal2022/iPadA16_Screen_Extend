import AVFoundation

/// Keeps the app's audio session in playback mode so the user can route sound
/// to the iPad speakers, headphones or HDMI from the in-app route picker.
final class AudioManager {
    static let shared = AudioManager()
    private init() {}

    func configure() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            print("AudioManager: failed to configure session: \(error)")
        }
    }

    /// Fallback if the system picker does not offer the built-in speaker while HDMI is attached.
    func forceBuiltInSpeaker(_ enabled: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if enabled {
                try session.setCategory(.playAndRecord, mode: .moviePlayback, options: [.defaultToSpeaker, .allowBluetoothA2DP])
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.overrideOutputAudioPort(.none)
                try session.setCategory(.playback, mode: .moviePlayback, options: [])
            }
            try session.setActive(true)
        } catch {
            print("AudioManager: speaker override failed: \(error)")
        }
    }
}
