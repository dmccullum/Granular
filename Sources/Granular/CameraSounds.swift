import AppKit
import AVFoundation

/// The camera's mechanical cues, read from `Contents/Resources/Sounds`.
/// A cue with no file in the bundle is silent, which is every cue under a
/// bare `swift run`.
final class CameraSounds {
    enum Cue: String, CaseIterable {
        /// A frame is exposed in the Instant gate, or an export finishes in Edit.
        case shutter
        /// The film advances one frame.
        case windOn = "wind-on"
        /// The canister drops into its pocket.
        case canisterSeat = "canister-seat"
    }

    static let shared = CameraSounds()

    private var players: [Cue: AVAudioPlayer] = [:]

    private init() {
        for cue in Cue.allCases {
            guard let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "caf", subdirectory: "Sounds"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[cue] = player
        }
    }

    /// Plays from the start, cutting off the same cue if it's still sounding.
    /// Silent while Granular is in the background.
    func play(_ cue: Cue) {
        guard NSApp.isActive, let player = players[cue] else { return }
        player.currentTime = 0
        player.play()
    }
}

extension AppModel {
    /// Plays a camera cue unless “Play camera sounds” is off in Settings.
    func playSound(_ cue: CameraSounds.Cue) {
        guard playsCameraSounds else { return }
        CameraSounds.shared.play(cue)
    }
}
