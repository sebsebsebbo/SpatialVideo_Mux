import SwiftUI
import UniformTypeIdentifiers
import AVKit
import AVFoundation

// MARK: - 1. CONFIGURATION & MODELS
// --------------------------------------------------------
// Defining our exact supported formats. Using 'Identifiable' and 'CaseIterable'
// makes it trivial for SwiftUI to render this dynamically in a menu.
enum ExportFormat: String, CaseIterable, Identifiable {
    case hsbs = "3D HSBS"
    case fsbs = "3D FSBS"

    var id: Self { self }

    // Options surfaced in the picker. Both supported formats ship, so this is
    // simply every case.
    static var releaseCases: [ExportFormat] { allCases }

    // Per-eye width in pixels; height is always 1080. HSBS halves each eye
    // (960×1080 → 1920×1080 total); FSBS keeps native (1920×1080 → 3840×1080).
    // nonisolated so the ExportManager actor can read it off the main actor.
    nonisolated var eyeWidth: Int {
        switch self {
        case .hsbs: return 960
        case .fsbs: return 1920
        }
    }

    var description: String {
        switch self {
        case .hsbs:
            return "Half Side-by-side\n Upload to YouTube for best VR and 3D TV playback."
        case .fsbs:
            return "Full Side-by-side\n Full resolution left and right eye (1920×1080 each view) mounted side by side. Not great for Youtube 3D playback."
        }
    }
}
