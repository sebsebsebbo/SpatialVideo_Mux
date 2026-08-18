import SwiftUI
import UniformTypeIdentifiers
import AVKit
import AVFoundation

// MARK: - 1. CONFIGURATION & MODELS
// --------------------------------------------------------
// Defining our exact supported formats. Using 'Identifiable' and 'CaseIterable'
// makes it trivial for SwiftUI to render this dynamically in a menu.
enum ExportFormat: String, CaseIterable, Identifiable {
    case fsbs = "FSBS"
    case hsbs = "HSBS"


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
        case .fsbs: return "Full Side-by-side\n Upload FSBS to YouTube for best VR playback (correct 16:9 aspect ratio)."
        case .hsbs: return "Half Side-by-side\n Do not upload HSBS to YouTube as this squeezes the image."
        }
    }
}

// Custom Error types so if the pipeline fails, we know exactly which step broke
enum ExportError: Error, LocalizedError {
    case ffmpegMissing
    case ffmpegFailed(code: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing: return "FFmpeg binary is missing from the App Bundle."
        case .ffmpegFailed(let code, let detail):
            let reason = detail.isEmpty ? "" : "\n\(detail)"
            return "FFmpeg process failed with exit code \(code).\(reason)"
        }
    }
}

// MARK: - 2. USER INTERFACE
// --------------------------------------------------------

// A concrete AppKit wrapper around AVPlayerView, used instead of SwiftUI's AVKit
// `VideoPlayer`. In optimized (Release/archive) builds, instantiating the generic
// metadata for `VideoPlayer<EmptyView>`'s internal representable aborts at runtime
// (_AVKit_SwiftUI __swift_instantiateGenericMetadata → getSuperclassMetadata →
// fatalError). A concrete NSViewRepresentable in our own module has its metadata
// emitted at compile time, so it never hits that AVKit-SwiftUI generic path.
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

struct ContentView: View {
    @State private var isShowingPicker = false
    @State private var selectedVideoURL: URL?
    @State private var player: AVPlayer?
    @State private var selectedFormat: ExportFormat = .fsbs
    @State private var enable3DTag = true   // Inject the stereo_mode 3D tag on export (stage 2)

    // NEW: Tracks export state so we can show a progress bar and lock the UI
    @State private var isExporting = false
    @State private var exportMessage = ""
    @State private var exportProgress: Double = 0      // 0.0 ... 1.0 completion
    @State private var exportStartDate: Date?          // When the current export began
    @State private var isShowingLicense = false        // Presents the About & Licensing sheet
    @State private var isShowingNotSpatialAlert = false // Shown when a non-spatial video is picked
    @State private var exportTask: Task<Void, Never>?  // The running export, so it can be cancelled

    var body: some View {
        ZStack {
            // Main Content Stack
            VStack(spacing: 20) {
                
                // Video Player Area
                if let activePlayer = player {
                    PlayerView(player: activePlayer)
                        .frame(height: 300)
                        .cornerRadius(10)
                } else {
                    // Shown until a video is selected, then the VideoPlayer above
                    // replaces this whole branch.
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 300)
                        .overlay(
                            VStack(spacing: 12) {
                                Image("AppLogo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 320)
                                Text("No video selected")
                                    .foregroundColor(.secondary)
                            }
                        )
                        .cornerRadius(10)
                }

                if let videoURL = selectedVideoURL {
                    Text("Selected: \(videoURL.lastPathComponent)")
                        .font(.headline)
                }

                Button("Select Spatial Video") {
                    isShowingPicker = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 10)
                .disabled(isExporting) // Disable while exporting
                
                // Export Settings Area
                VStack(spacing: 5) {
                    Picker("Export Format:", selection: $selectedFormat) {
                        ForEach(ExportFormat.releaseCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 300)
                    .disabled(isExporting)
                    
                    Text(selectedFormat.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    // When ticked, stage 2 injects the stereo_mode 3D tag so
                    // YouTube treats the upload as side-by-side 3D. Unticked exports
                    // the plain side-by-side video with no tag.
                    Toggle("Enable 3D YouTube injection tag", isOn: $enable3DTag)
                        .toggleStyle(.checkbox)
                        .disabled(isExporting)
                        .padding(.top, 4)
                }
                .padding(.bottom, 10)

                // Export Trigger Button
                Button("Export Video") {
                    startExportProcess()
                }
                .buttonStyle(.bordered)
                .disabled(selectedVideoURL == nil || isExporting)

                // Encourage sharing after an export.
                VStack(spacing: 2) {
                    Text("Remember to UPLOAD to YouTube and SHARE your 3D Videos!")
                        .bold()
                    Text("**Tell your friends** to **watch in VR!!**")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

                HStack(spacing: 20) {
                    // Opens YouTube's upload page (redirects into YouTube Studio once
                    // the user is signed in). Just an external web link — no API access.
                    Button {
                        if let url = URL(string: "https://www.youtube.com/upload") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Upload to YouTube", systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .tint(.red)

                    // Support / Tip button — opens an external donation page in the browser.
                    // The app ships outside the App Store, so external payment links are
                    // allowed (no in-app-purchase requirement)
                    Button {
                        if let url = URL(string: "https://ko-fi.com/ohsebseb") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Support this app", systemImage: "heart.fill")
                    }
                    .buttonStyle(.borderless)
                    .tint(.pink)
                }
                .padding(.top, 4)
                .disabled(isExporting)

                // Opens a sheet with the GPL notice and a link to the corresponding
                // source code (required for GPL compliance). Placed below the
                // YouTube/Support links.
                Button {
                    isShowingLicense = true
                } label: {
                    Label("About & Licensing", systemImage: "info.circle")
                }
                .buttonStyle(.borderless)
                .tint(.secondary)
                .disabled(isExporting)
            }
            .padding(50)
            .frame(width: 500, height: 650)
            
            // NEW: Loading Overlay
            // Dims the screen and shows a determinate progress bar when isExporting == true
            if isExporting {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    Text(exportMessage)
                        .bold()
                        .foregroundColor(.white)

                    ProgressView(value: exportProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 260)
                        .tint(.white)

                    Text("\(Int(exportProgress * 100))%")
                        .font(.headline.monospacedDigit())
                        .foregroundColor(.white)

                    // Live "time remaining" estimate, updated every 1 second (no Combine).
                    // We project the total time from how long the current progress took,
                    // then subtract elapsed. Needs a little progress before it's meaningful.
                    if let start = exportStartDate {
                        TimelineView(.periodic(from: start, by: 1)) { context in
                            let elapsed = context.date.timeIntervalSince(start)
                            if exportProgress > 0.02, elapsed > 0.5 {
                                let estimatedTotal = elapsed / exportProgress
                                let remaining = Int(max(estimatedTotal - elapsed, 0).rounded())
                                Text("Time remaining: \(remaining / 60):\(String(format: "%02d", remaining % 60))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.white.opacity(0.8))
                            } else {
                                Text("Estimating time remaining…")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }

                    // Cancel stops the pipeline, deletes the partial output file, and
                    // returns to the main screen. Disabled once we're winding down so
                    // it can't fire during the brief "complete/cancelled" message.
                    Button("Cancel") {
                        exportMessage = "Cancelling…"
                        exportTask?.cancel()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.top, 4)
                }
                .padding(30)
                .background(.thickMaterial)
                .cornerRadius(15)
            }
        }
        .fileImporter(
            isPresented: $isShowingPicker,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .sheet(isPresented: $isShowingLicense) {
            LicenseView()
        }
        .alert("Not a Spatial 3D Video", isPresented: $isShowingNotSpatialAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This file isn’t a spatial 3D (MV-HEVC stereoscopic) video, so there are no separate left/right eyes to convert. Please select a spatial video, such as one captured on iPhone 15 Pro or later, or Apple Vision Pro.")
        }
    }
    
    // MARK: UI Helper Functions
    
    // Extracted file handling to keep the View body clean
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            // Only accept spatial (MV-HEVC stereo multiview) videos. Anything else has
            // no second eye to extract, so we reject it with a clear message instead of
            // letting the user run an export that would silently produce a fake 3D result.
            Task {
                if await ExportManager.shared.isSpatialVideo(url: url) {
                    selectedVideoURL = url
                    player = AVPlayer(url: url)
                    player?.play()
                } else {
                    url.stopAccessingSecurityScopedResource()
                    isShowingNotSpatialAlert = true
                }
            }
        case .failure(let error):
            print("File selection error: \(error.localizedDescription)")
        }
    }
    
    // Handles the UI coordination for the async export pipeline
    private func startExportProcess() {
        guard let sourceURL = selectedVideoURL else { return }

        let savePanel = NSSavePanel()
        // MP4 output — the proven format for YouTube SBS 3D. When 3D injection is
        // enabled the H.264 frame-packing SEI is written into this .mp4.
        savePanel.allowedContentTypes = [.mpeg4Movie]
        savePanel.nameFieldStringValue = "YouTube_3D_Video.mp4"
        savePanel.title = "Save Final 3D Video"
        
        savePanel.begin { response in
            if response == .OK, let destinationURL = savePanel.url {
                
                // 1. Lock the UI and reset the progress bar
                isExporting = true
                exportProgress = 0
                exportStartDate = Date()
                exportMessage = "Extracting spatial frames..."

                // 2. Launch a cancellable Task to run our background async code.
                //    Held in `exportTask` so the Cancel button can stop it.
                exportTask = Task {
                    // Progress callback forwards updates (0.0...1.0) back onto the
                    // main actor to drive the bar. Shared by both pipelines.
                    let onProgress: @Sendable (Double) -> Void = { fraction in
                        Task { @MainActor in
                            exportProgress = fraction
                            exportMessage = fraction < 0.5
                                ? "Extracting spatial frames..."
                                : "Encoding final video..."
                        }
                    }
                    var wasCancelled = false
                    do {
                        // 3. Run the FFmpeg export pipeline.
                        try await ExportManager.shared.processVideo(
                            source: sourceURL,
                            destination: destinationURL,
                            format: selectedFormat,
                            injectTag: enable3DTag,
                            onProgress: onProgress
                        )
                        exportProgress = 1.0
                        exportMessage = "Export Complete!"
                    } catch is CancellationError {
                        // User cancelled: make sure no partial output is left behind.
                        wasCancelled = true
                        try? FileManager.default.removeItem(at: destinationURL)
                        exportMessage = "Export Cancelled"
                    } catch {
                        print("Export failed: \(error)")
                        exportMessage = "Export Failed: \(error.localizedDescription)"
                    }

                    // 4. On cancel, return to the main screen immediately; otherwise
                    //    hold the success/fail message briefly so it can be read.
                    if !wasCancelled {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                    isExporting = false
                    exportTask = nil
                }
            }
        }
    }
}

// MARK: - About & Licensing
// Displays the GPL notice and a link to the corresponding source code.
// Showing this is required for compliance, since the app bundles FFmpeg (GPL).
struct LicenseView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingFullLicense = false   // Presents the full GPL v3 text

    private let ffmpegSourceURL = "https://github.com/FFmpeg/FFmpeg/"
    private let x264SourceURL = "https://code.videolan.org/videolan/x264"
    private let licenseURL = "https://www.gnu.org/licenses/gpl-3.0.html"
    private let authorURL = "https://github.com/sebsebsebbo"
    private let coAuthorURL = "https://claude.com/claude-code"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About & Licensing")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 2) {
                Text("Copyright © 2026 Sebastian Gonzalez Agero.")
                Text("GPLv3 License.")
            }
            .font(.callout)
            .foregroundColor(.secondary)

            HStack(spacing: 4) {
                Text("AI Code:")
                Link("Claude", destination: URL(string: coAuthorURL)!)
                Text("·")
                Text("Prompts & Xcode")
                Link("sebsebsebbo", destination: URL(string: authorURL)!)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("This app includes software developed by:")
            
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("• The FFmpeg Project")
                    Text("This software uses libraries from the FFmpeg project, which is licensed under the GNU General Public License (GPL).")
                    Text("https://ffmpeg.org")
                    Text("Copyright (c) 2000-2026 the FFmpeg developers")
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("• The x264 Project:")
                    Text("This software utilizes the x264 video encoding library, copyright © VideoLAN, licensed under the GNU General Public License (GPL).")
                    Text("https://www.videolan.org/developers/x264.html")
                    Text("Copyright (C) 2003-2026 x264 project")
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                }
                
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("The corresponding source code for")
                Text("the bundled GPL components is available at:")
                Link("FFmpeg", destination: URL(string: ffmpegSourceURL)!)
                Link("x264", destination: URL(string: x264SourceURL)!)
            }
            HStack(spacing:1){
                Text("With thanks to the FFmpeg development team and the x264 project for their software, and for both my partner Matt for suffering through this, plus Claude and Gemini for helping me persevere.")
            }
                .padding(.top, 4)

            Divider()

            // Notice for the bundled FFmpeg component (runs as a separate program).
            Group {
                // Reads the full license text bundled in-app (below), so users can
                // view it offline. The external link is kept as a convenient fallback.
                Button("Read the full GNU GPL v3 license") {
                    isShowingFullLicense = true
                }
                .buttonStyle(.link)
                Link("Open the GNU GPL v3 license online", destination: URL(string: licenseURL)!)
            }
            .font(.callout)
            .foregroundColor(.secondary)

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .sheet(isPresented: $isShowingFullLicense) {
            FullLicenseTextView()
        }
    }
}

// Scrollable view of the complete GNU GPL v3 license text, bundled in-app so the
// license travels with the binary (GPL compliance) and is readable offline.
struct FullLicenseTextView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GNU General Public License v3")
                .font(.title3.bold())

            ScrollView {
                Text(gplV3LicenseText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 400)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640, height: 560)
    }
}

#Preview {
    ContentView()
}

// MARK: - 3. THE VIDEO PROCESSING ENGINE
// --------------------------------------------------------
// Collapses many per-frame progress updates down to one per whole percent,
// so we don't spam the main actor. Accessed only from a single serial queue,
// which is why the unchecked Sendable conformance is safe here.
private nonisolated final class ProgressThrottle: @unchecked Sendable {
    private var lastPercent = -1
    func shouldReport(_ fraction: Double) -> Bool {
        let percent = Int(fraction * 100)
        guard percent > lastPercent else { return false }
        lastPercent = percent
        return true
    }
}

// We use an 'actor' instead of a 'class'. Actors guarantee that if multiple
// tasks try to use the ExportManager at once, they won't crash the app by stepping on each other.
actor ExportManager {
    static let shared = ExportManager()
    
    // The Master Pipeline is a single FFmpeg pass: decode both MV-HEVC eye views,
    // scale them, lay them side by side, and re-encode to H.264 in an .mp4. When
    // `injectTag` is true the same pass also writes the H.264 frame-packing SEI.
    // `onProgress` reports 0.0...1.0.
    func processVideo(source: URL,
                      destination: URL,
                      format: ExportFormat,
                      injectTag: Bool,
                      onProgress: @escaping @Sendable (Double) -> Void) async throws {

        // Overwrite any existing file at the destination.
        try? FileManager.default.removeItem(at: destination)

        // Total duration lets us translate FFmpeg's progress into a 0...1 fraction.
        let durationSeconds = try await AVURLAsset(url: source).load(.duration).seconds

        do {
            try await runFFmpeg(source: source,
                                destination: destination,
                                format: format,
                                tag3D: injectTag,
                                duration: durationSeconds,
                                onProgress: onProgress)
            onProgress(1.0)
        } catch {
            // Never leave a partial file at the user's chosen location.
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
    
    // MARK: - Spatial Video Validation
    // Returns true only if the file's video track is a spatial (MV-HEVC stereo
    // multiview) recording — i.e. it actually carries two eye views. Used to gate
    // file selection so non-spatial videos are rejected up front. Uses the modern
    // load(.mediaCharacteristics) API (not the deprecated hasMediaCharacteristic).
    func isSpatialVideo(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let characteristics = try? await track.load(.mediaCharacteristics) else {
            return false
        }
        return characteristics.contains(.containsStereoMultiviewVideo)
    }

    // Locates the FFmpeg (arm64) binary bundled into the app at build time. Checks
    // Contents/MacOS (forAuxiliaryExecutable, Apple's preferred spot for helper
    // tools) first, then Resources — so either bundling style works. There is no
    // dev fallback; if the bundled binary is missing we fail fast with ffmpegMissing.
    private func locateFFmpeg() throws -> URL {
        guard let ffmpegURL = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg")
            ?? Bundle.main.url(forResource: "ffmpeg", withExtension: nil) else {
            throw ExportError.ffmpegMissing
        }
        // Log the exact binary being used so it's easy to confirm which build is bundled.
        print("[SpatialVideo_Mux] Using ffmpeg at: \(ffmpegURL.path)")
        return ffmpegURL
    }

    // MARK: - FFmpeg: Build (and optionally tag) the side-by-side video
    // Decodes both MV-HEVC eye views with view specifiers, scales each to the target
    // eye size, and stacks them horizontally into a re-encoded H.264 .mp4. Audio is
    // copied through. When `tag3D` is true, the same encode also writes the H.264
    // frame-packing SEI (via libx264) for YouTube SBS 3D.
    private func runFFmpeg(source: URL,
                           destination: URL,
                           format: ExportFormat,
                           tag3D: Bool,
                           duration: Double,
                           onProgress: @escaping @Sendable (Double) -> Void) async throws {

        let process = Process()
        process.executableURL = try locateFFmpeg()

        // Only the per-eye size differs between formats:
        //    - HSBS: 960×1080 per eye  → 1920×1080 total.
        //    - FSBS: 1920×1080 per eye → 3840×1080 total.
        let eyeWidth = (format == .hsbs) ? 960 : 1920
        let eyeHeight = 1080

        // FFmpeg view specifiers pull the two MV-HEVC eyes straight from the source.
        // On these files view 1 is the LEFT eye and view 0 is the RIGHT eye, so we
        // feed view 1 into the left half and view 0 into the right, then stack L | R.
        // For the tagged YouTube output, normalise the final stacked frame to the
        // format's full size with square pixels (HSBS 1920x1080, FSBS 3840x1080) so
        // YouTube reports the expected SBS 3D resolution. This must live inside the
        // filtergraph — a separate -vf can't touch a -filter_complex output.
        let totalWidth = eyeWidth * 2   // HSBS: 1920, FSBS: 3840
        let finalStack = tag3D
            ? "[l][r]hstack=inputs=2,scale=\(totalWidth):\(eyeHeight),setsar=1[v]"
            : "[l][r]hstack=inputs=2[v]"
        let filter = "[0:v:0:view:1]scale=\(eyeWidth):\(eyeHeight),setsar=1[l];"
                   + "[0:v:0:view:0]scale=\(eyeWidth):\(eyeHeight),setsar=1[r];"
                   + finalStack

        var arguments: [String] = [
            "-i", source.path,
            "-filter_complex", filter,
            "-map", "[v]",             // the stacked side-by-side video from the filtergraph
            "-map", "0:a:0?",          // copy the original audio if present ("?" = optional)
            "-c:v", "libx264",               // Codec
            "-profile:v", "high",            // Profile
            "-level", "4.0",                 // Level
            "-fpsmax", "30",                 // Framerate cap
            "-pix_fmt", "yuv420p",           // Pixel format
        ]
        if tag3D {
            // frame-packing=3 writes the H.264 side-by-side 3D SEI (left eye first,
            // matching our L|R hstack). This is what YouTube reads for SBS 3D in an
            // .mp4 container.
            arguments += ["-x264opts", "frame-packing=3"]
            
        }
        // Copy the original audio untouched; -shortest guards against length drift.
        arguments += ["-c:a", "copy", "-shortest"]
        // Ask FFmpeg to emit machine-readable progress to stdout so we can drive the bar.
        arguments += ["-progress", "pipe:1", "-nostats", destination.path]
        process.arguments = arguments

        // Pipe FFmpeg's progress output and translate its `out_time` into a 0...1 fraction.
        let progressPipe = Pipe()
        process.standardOutput = progressPipe
        let throttle = ProgressThrottle()
        let lineBuffer = LineBuffer()
        if duration > 0 {
            progressPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                for line in lineBuffer.appendAndExtractLines(chunk) {
                    guard line.hasPrefix("out_time=") else { continue }
                    let value = String(line.dropFirst("out_time=".count))
                    guard let seconds = ExportManager.parseFFmpegTime(value) else { continue }
                    let progress = min(seconds / duration, 1.0)
                    if throttle.shouldReport(progress) {
                        onProgress(progress)
                    }
                }
            }
        }
        // Release the pipe handler once the process has finished (or failed).
        defer { progressPipe.fileHandleForReading.readabilityHandler = nil }

        try await runProcess(process, cleanupOnCancel: destination)
    }

    // Runs an FFmpeg process to completion. If the surrounding Task is cancelled
    // (user hit Cancel), terminates FFmpeg and deletes the partial output at
    // `cleanupOnCancel`, surfacing the stop as a CancellationError for the UI.
    private func runProcess(_ process: Process, cleanupOnCancel destination: URL) async throws {
        let processBox = ProcessBox(process)
        // Capture FFmpeg's stderr so a failure surfaces its real message, not just a
        // numeric exit code. With -nostats the volume is small, so reading it at
        // termination won't block the encode.
        let errorPipe = Pipe()
        process.standardError = errorPipe
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    do {
                        // terminationHandler fires automatically when FFmpeg finishes.
                        process.terminationHandler = { finishedProcess in
                            let status = Int(finishedProcess.terminationStatus)
                            if status == 0 {
                                continuation.resume()
                            } else {
                                // Keep the last few non-empty stderr lines — that's where
                                // FFmpeg prints the actual error.
                                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                                let detail = (String(data: data, encoding: .utf8) ?? "")
                                    .split(separator: "\n", omittingEmptySubsequences: true)
                                    .suffix(4)
                                    .joined(separator: "\n")
                                continuation.resume(throwing: ExportError.ffmpegFailed(code: status, detail: detail))
                            }
                        }
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } onCancel: {
                processBox.process.terminate()
            }
        } catch {
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: destination)
                throw CancellationError()
            }
            throw error
        }
    }

    // Converts FFmpeg's "HH:MM:SS.micro" timestamp into seconds. Returns nil for "N/A".
    private static func parseFFmpegTime(_ text: String) -> Double? {
        let parts = text.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}

// Lets a running Process be terminated from a task-cancellation handler. Process
// isn't Sendable, but the only cross-domain use here is calling terminate(), so
// unchecked Sendable is safe (matches the file's other pipe/throttle helpers).
private nonisolated final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}


// Reassembles arbitrary byte chunks from a pipe into complete newline-terminated
// lines, holding back any trailing partial line until the rest arrives. Accessed
// only from the pipe's serial reading queue, so unchecked Sendable is safe.
private nonisolated final class LineBuffer: @unchecked Sendable {
    private var partial = ""
    func appendAndExtractLines(_ chunk: String) -> [String] {
        partial += chunk
        var lines = partial.components(separatedBy: "\n")
        partial = lines.removeLast()   // keep the incomplete trailing fragment
        return lines
    }
}

// MARK: - GNU GPL v3 License Text
// Verbatim copy of the GNU General Public License, version 3, displayed by
// FullLicenseTextView. Bundled in-app so the license accompanies the binary as
// required when redistributing the GPL-licensed FFmpeg component.
let gplV3LicenseText = #"""
                    GNU GENERAL PUBLIC LICENSE
                       Version 3, 29 June 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The GNU General Public License is a free, copyleft license for
software and other kinds of works.

  The licenses for most software and other practical works are designed
to take away your freedom to share and change the works.  By contrast,
the GNU General Public License is intended to guarantee your freedom to
share and change all versions of a program--to make sure it remains free
software for all its users.  We, the Free Software Foundation, use the
GNU General Public License for most of our software; it applies also to
any other work released this way by its authors.  You can apply it to
your programs, too.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
them if you wish), that you receive source code or can get it if you
want it, that you can change the software or use pieces of it in new
free programs, and that you know you can do these things.

  To protect your rights, we need to prevent others from denying you
these rights or asking you to surrender the rights.  Therefore, you have
certain responsibilities if you distribute copies of the software, or if
you modify it: responsibilities to respect the freedom of others.

  For example, if you distribute copies of such a program, whether
gratis or for a fee, you must pass on to the recipients the same
freedoms that you received.  You must make sure that they, too, receive
or can get the source code.  And you must show them these terms so they
know their rights.

  Developers that use the GNU GPL protect your rights with two steps:
(1) assert copyright on the software, and (2) offer you this License
giving you legal permission to copy, distribute and/or modify it.

  For the developers' and authors' protection, the GPL clearly explains
that there is no warranty for this free software.  For both users' and
authors' sake, the GPL requires that modified versions be marked as
changed, so that their problems will not be attributed erroneously to
authors of previous versions.

  Some devices are designed to deny users access to install or run
modified versions of the software inside them, although the manufacturer
can do so.  This is fundamentally incompatible with the aim of
protecting users' freedom to change the software.  The systematic
pattern of such abuse occurs in the area of products for individuals to
use, which is precisely where it is most unacceptable.  Therefore, we
have designed this version of the GPL to prohibit the practice for those
products.  If such problems arise substantially in other domains, we
stand ready to extend this provision to those domains in future versions
of the GPL, as needed to protect the freedom of users.

  Finally, every program is threatened constantly by software patents.
States should not allow patents to restrict development and use of
software on general-purpose computers, but in those that do, we wish to
avoid the special danger that patents applied to a free program could
make it effectively proprietary.  To prevent this, the GPL assures that
patents cannot be used to render the program non-free.

  The precise terms and conditions for copying, distribution and
modification follow.

                       TERMS AND CONDITIONS

  0. Definitions.

  "This License" refers to version 3 of the GNU General Public License.

  "Copyright" also means copyright-like laws that apply to other kinds of
works, such as semiconductor masks.

  "The Program" refers to any copyrightable work licensed under this
License.  Each licensee is addressed as "you".  "Licensees" and
"recipients" may be individuals or organizations.

  To "modify" a work means to copy from or adapt all or part of the work
in a fashion requiring copyright permission, other than the making of an
exact copy.  The resulting work is called a "modified version" of the
earlier work or a work "based on" the earlier work.

  A "covered work" means either the unmodified Program or a work based
on the Program.

  To "propagate" a work means to do anything with it that, without
permission, would make you directly or secondarily liable for
infringement under applicable copyright law, except executing it on a
computer or modifying a private copy.  Propagation includes copying,
distribution (with or without modification), making available to the
public, and in some countries other activities as well.

  To "convey" a work means any kind of propagation that enables other
parties to make or receive copies.  Mere interaction with a user through
a computer network, with no transfer of a copy, is not conveying.

  An interactive user interface displays "Appropriate Legal Notices"
to the extent that it includes a convenient and prominently visible
feature that (1) displays an appropriate copyright notice, and (2)
tells the user that there is no warranty for the work (except to the
extent that warranties are provided), that licensees may convey the
work under this License, and how to view a copy of this License.  If
the interface presents a list of user commands or options, such as a
menu, a prominent item in the list meets this criterion.

  1. Source Code.

  The "source code" for a work means the preferred form of the work
for making modifications to it.  "Object code" means any non-source
form of a work.

  A "Standard Interface" means an interface that either is an official
standard defined by a recognized standards body, or, in the case of
interfaces specified for a particular programming language, one that
is widely used among developers working in that language.

  The "System Libraries" of an executable work include anything, other
than the work as a whole, that (a) is included in the normal form of
packaging a Major Component, but which is not part of that Major
Component, and (b) serves only to enable use of the work with that
Major Component, or to implement a Standard Interface for which an
implementation is available to the public in source code form.  A
"Major Component", in this context, means a major essential component
(kernel, window system, and so on) of the specific operating system
(if any) on which the executable work runs, or a compiler used to
produce the work, or an object code interpreter used to run it.

  The "Corresponding Source" for a work in object code form means all
the source code needed to generate, install, and (for an executable
work) run the object code and to modify the work, including scripts to
control those activities.  However, it does not include the work's
System Libraries, or general-purpose tools or generally available free
programs which are used unmodified in performing those activities but
which are not part of the work.  For example, Corresponding Source
includes interface definition files associated with source files for
the work, and the source code for shared libraries and dynamically
linked subprograms that the work is specifically designed to require,
such as by intimate data communication or control flow between those
subprograms and other parts of the work.

  The Corresponding Source need not include anything that users
can regenerate automatically from other parts of the Corresponding
Source.

  The Corresponding Source for a work in source code form is that
same work.

  2. Basic Permissions.

  All rights granted under this License are granted for the term of
copyright on the Program, and are irrevocable provided the stated
conditions are met.  This License explicitly affirms your unlimited
permission to run the unmodified Program.  The output from running a
covered work is covered by this License only if the output, given its
content, constitutes a covered work.  This License acknowledges your
rights of fair use or other equivalent, as provided by copyright law.

  You may make, run and propagate covered works that you do not
convey, without conditions so long as your license otherwise remains
in force.  You may convey covered works to others for the sole purpose
of having them make modifications exclusively for you, or provide you
with facilities for running those works, provided that you comply with
the terms of this License in conveying all material for which you do
not control copyright.  Those thus making or running the covered works
for you must do so exclusively on your behalf, under your direction
and control, on terms that prohibit them from making any copies of
your copyrighted material outside their relationship with you.

  Conveying under any other circumstances is permitted solely under
the conditions stated below.  Sublicensing is not allowed; section 10
makes it unnecessary.

  3. Protecting Users' Legal Rights From Anti-Circumvention Law.

  No covered work shall be deemed part of an effective technological
measure under any applicable law fulfilling obligations under article
11 of the WIPO copyright treaty adopted on 20 December 1996, or
similar laws prohibiting or restricting circumvention of such
measures.

  When you convey a covered work, you waive any legal power to forbid
circumvention of technological measures to the extent such circumvention
is effected by exercising rights under this License with respect to
the covered work, and you disclaim any intention to limit operation or
modification of the work as a means of enforcing, against the work's
users, your or third parties' legal rights to forbid circumvention of
technological measures.

  4. Conveying Verbatim Copies.

  You may convey verbatim copies of the Program's source code as you
receive it, in any medium, provided that you conspicuously and
appropriately publish on each copy an appropriate copyright notice;
keep intact all notices stating that this License and any
non-permissive terms added in accord with section 7 apply to the code;
keep intact all notices of the absence of any warranty; and give all
recipients a copy of this License along with the Program.

  You may charge any price or no price for each copy that you convey,
and you may offer support or warranty protection for a fee.

  5. Conveying Modified Source Versions.

  You may convey a work based on the Program, or the modifications to
produce it from the Program, in the form of source code under the
terms of section 4, provided that you also meet all of these conditions:

    a) The work must carry prominent notices stating that you modified
    it, and giving a relevant date.

    b) The work must carry prominent notices stating that it is
    released under this License and any conditions added under section
    7.  This requirement modifies the requirement in section 4 to
    "keep intact all notices".

    c) You must license the entire work, as a whole, under this
    License to anyone who comes into possession of a copy.  This
    License will therefore apply, along with any applicable section 7
    additional terms, to the whole of the work, and all its parts,
    regardless of how they are packaged.  This License gives no
    permission to license the work in any other way, but it does not
    invalidate such permission if you have separately received it.

    d) If the work has interactive user interfaces, each must display
    Appropriate Legal Notices; however, if the Program has interactive
    interfaces that do not display Appropriate Legal Notices, your
    work need not make them do so.

  A compilation of a covered work with other separate and independent
works, which are not by their nature extensions of the covered work,
and which are not combined with it such as to form a larger program,
in or on a volume of a storage or distribution medium, is called an
"aggregate" if the compilation and its resulting copyright are not
used to limit the access or legal rights of the compilation's users
beyond what the individual works permit.  Inclusion of a covered work
in an aggregate does not cause this License to apply to the other
parts of the aggregate.

  6. Conveying Non-Source Forms.

  You may convey a covered work in object code form under the terms
of sections 4 and 5, provided that you also convey the
machine-readable Corresponding Source under the terms of this License,
in one of these ways:

    a) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by the
    Corresponding Source fixed on a durable physical medium
    customarily used for software interchange.

    b) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by a
    written offer, valid for at least three years and valid for as
    long as you offer spare parts or customer support for that product
    model, to give anyone who possesses the object code either (1) a
    copy of the Corresponding Source for all the software in the
    product that is covered by this License, on a durable physical
    medium customarily used for software interchange, for a price no
    more than your reasonable cost of physically performing this
    conveying of source, or (2) access to copy the
    Corresponding Source from a network server at no charge.

    c) Convey individual copies of the object code with a copy of the
    written offer to provide the Corresponding Source.  This
    alternative is allowed only occasionally and noncommercially, and
    only if you received the object code with such an offer, in accord
    with subsection 6b.

    d) Convey the object code by offering access from a designated
    place (gratis or for a charge), and offer equivalent access to the
    Corresponding Source in the same way through the same place at no
    further charge.  You need not require recipients to copy the
    Corresponding Source along with the object code.  If the place to
    copy the object code is a network server, the Corresponding Source
    may be on a different server (operated by you or a third party)
    that supports equivalent copying facilities, provided you maintain
    clear directions next to the object code saying where to find the
    Corresponding Source.  Regardless of what server hosts the
    Corresponding Source, you remain obligated to ensure that it is
    available for as long as needed to satisfy these requirements.

    e) Convey the object code using peer-to-peer transmission, provided
    you inform other peers where the object code and Corresponding
    Source of the work are being offered to the general public at no
    charge under subsection 6d.

  A separable portion of the object code, whose source code is excluded
from the Corresponding Source as a System Library, need not be
included in conveying the object code work.

  A "User Product" is either (1) a "consumer product", which means any
tangible personal property which is normally used for personal, family,
or household purposes, or (2) anything designed or sold for incorporation
into a dwelling.  In determining whether a product is a consumer product,
doubtful cases shall be resolved in favor of coverage.  For a particular
product received by a particular user, "normally used" refers to a
typical or common use of that class of product, regardless of the status
of the particular user or of the way in which the particular user
actually uses, or expects or is expected to use, the product.  A product
is a consumer product regardless of whether the product has substantial
commercial, industrial or non-consumer uses, unless such uses represent
the only significant mode of use of the product.

  "Installation Information" for a User Product means any methods,
procedures, authorization keys, or other information required to install
and execute modified versions of a covered work in that User Product from
a modified version of its Corresponding Source.  The information must
suffice to ensure that the continued functioning of the modified object
code is in no case prevented or interfered with solely because
modification has been made.

  If you convey an object code work under this section in, or with, or
specifically for use in, a User Product, and the conveying occurs as
part of a transaction in which the right of possession and use of the
User Product is transferred to the recipient in perpetuity or for a
fixed term (regardless of how the transaction is characterized), the
Corresponding Source conveyed under this section must be accompanied
by the Installation Information.  But this requirement does not apply
if neither you nor any third party retains the ability to install
modified object code on the User Product (for example, the work has
been installed in ROM).

  The requirement to provide Installation Information does not include a
requirement to continue to provide support service, warranty, or updates
for a work that has been modified or installed by the recipient, or for
the User Product in which it has been modified or installed.  Access to a
network may be denied when the modification itself materially and
adversely affects the operation of the network or violates the rules and
protocols for communication across the network.

  Corresponding Source conveyed, and Installation Information provided,
in accord with this section must be in a format that is publicly
documented (and with an implementation available to the public in
source code form), and must require no special password or key for
unpacking, reading or copying.

  7. Additional Terms.

  "Additional permissions" are terms that supplement the terms of this
License by making exceptions from one or more of its conditions.
Additional permissions that are applicable to the entire Program shall
be treated as though they were included in this License, to the extent
that they are valid under applicable law.  If additional permissions
apply only to part of the Program, that part may be used separately
under those permissions, but the entire Program remains governed by
this License without regard to the additional permissions.

  When you convey a copy of a covered work, you may at your option
remove any additional permissions from that copy, or from any part of
it.  (Additional permissions may be written to require their own
removal in certain cases when you modify the work.)  You may place
additional permissions on material, added by you to a covered work,
for which you have or can give appropriate copyright permission.

  Notwithstanding any other provision of this License, for material you
add to a covered work, you may (if authorized by the copyright holders of
that material) supplement the terms of this License with terms:

    a) Disclaiming warranty or limiting liability differently from the
    terms of sections 15 and 16 of this License; or

    b) Requiring preservation of specified reasonable legal notices or
    author attributions in that material or in the Appropriate Legal
    Notices displayed by works containing it; or

    c) Prohibiting misrepresentation of the origin of that material, or
    requiring that modified versions of such material be marked in
    reasonable ways as different from the original version; or

    d) Limiting the use for publicity purposes of names of licensors or
    authors of the material; or

    e) Declining to grant rights under trademark law for use of some
    trade names, trademarks, or service marks; or

    f) Requiring indemnification of licensors and authors of that
    material by anyone who conveys the material (or modified versions of
    it) with contractual assumptions of liability to the recipient, for
    any liability that these contractual assumptions directly impose on
    those licensors and authors.

  All other non-permissive additional terms are considered "further
restrictions" within the meaning of section 10.  If the Program as you
received it, or any part of it, contains a notice stating that it is
governed by this License along with a term that is a further
restriction, you may remove that term.  If a license document contains
a further restriction but permits relicensing or conveying under this
License, you may add to a covered work material governed by the terms
of that license document, provided that the further restriction does
not survive such relicensing or conveying.

  If you add terms to a covered work in accord with this section, you
must place, in the relevant source files, a statement of the
additional terms that apply to those files, or a notice indicating
where to find the applicable terms.

  Additional terms, permissive or non-permissive, may be stated in the
form of a separately written license, or stated as exceptions;
the above requirements apply either way.

  8. Termination.

  You may not propagate or modify a covered work except as expressly
provided under this License.  Any attempt otherwise to propagate or
modify it is void, and will automatically terminate your rights under
this License (including any patent licenses granted under the third
paragraph of section 11).

  However, if you cease all violation of this License, then your
license from a particular copyright holder is reinstated (a)
provisionally, unless and until the copyright holder explicitly and
finally terminates your license, and (b) permanently, if the copyright
holder fails to notify you of the violation by some reasonable means
prior to 60 days after the cessation.

  Moreover, your license from a particular copyright holder is
reinstated permanently if the copyright holder notifies you of the
violation by some reasonable means, this is the first time you have
received notice of violation of this License (for any work) from that
copyright holder, and you cure the violation prior to 30 days after
your receipt of the notice.

  Termination of your rights under this section does not terminate the
licenses of parties who have received copies or rights from you under
this License.  If your rights have been terminated and not permanently
reinstated, you do not qualify to receive new licenses for the same
material under section 10.

  9. Acceptance Not Required for Having Copies.

  You are not required to accept this License in order to receive or
run a copy of the Program.  Ancillary propagation of a covered work
occurring solely as a consequence of using peer-to-peer transmission
to receive a copy likewise does not require acceptance.  However,
nothing other than this License grants you permission to propagate or
modify any covered work.  These actions infringe copyright if you do
not accept this License.  Therefore, by modifying or propagating a
covered work, you indicate your acceptance of this License to do so.

  10. Automatic Licensing of Downstream Recipients.

  Each time you convey a covered work, the recipient automatically
receives a license from the original licensors, to run, modify and
propagate that work, subject to this License.  You are not responsible
for enforcing compliance by third parties with this License.

  An "entity transaction" is a transaction transferring control of an
organization, or substantially all assets of one, or subdividing an
organization, or merging organizations.  If propagation of a covered
work results from an entity transaction, each party to that
transaction who receives a copy of the work also receives whatever
licenses to the work the party's predecessor in interest had or could
give under the previous paragraph, plus a right to possession of the
Corresponding Source of the work from the predecessor in interest, if
the predecessor has it or can get it with reasonable efforts.

  You may not impose any further restrictions on the exercise of the
rights granted or affirmed under this License.  For example, you may
not impose a license fee, royalty, or other charge for exercise of
rights granted under this License, and you may not initiate litigation
(including a cross-claim or counterclaim in a lawsuit) alleging that
any patent claim is infringed by making, using, selling, offering for
sale, or importing the Program or any portion of it.

  11. Patents.

  A "contributor" is a copyright holder who authorizes use under this
License of the Program or a work on which the Program is based.  The
work thus licensed is called the contributor's "contributor version".

  A contributor's "essential patent claims" are all patent claims
owned or controlled by the contributor, whether already acquired or
hereafter acquired, that would be infringed by some manner, permitted
by this License, of making, using, or selling its contributor version,
but do not include claims that would be infringed only as a
consequence of further modification of the contributor version.  For
purposes of this definition, "control" includes the right to grant
patent sublicenses in a manner consistent with the requirements of
this License.

  Each contributor grants you a non-exclusive, worldwide, royalty-free
patent license under the contributor's essential patent claims, to
make, use, sell, offer for sale, import and otherwise run, modify and
propagate the contents of its contributor version.

  In the following three paragraphs, a "patent license" is any express
agreement or commitment, however denominated, not to enforce a patent
(such as an express permission to practice a patent or covenant not to
sue for patent infringement).  To "grant" such a patent license to a
party means to make such an agreement or commitment not to enforce a
patent against the party.

  If you convey a covered work, knowingly relying on a patent license,
and the Corresponding Source of the work is not available for anyone
to copy, free of charge and under the terms of this License, through a
publicly available network server or other readily accessible means,
then you must either (1) cause the Corresponding Source to be so
available, or (2) arrange to deprive yourself of the benefit of the
patent license for this particular work, or (3) arrange, in a manner
consistent with the requirements of this License, to extend the patent
license to downstream recipients.  "Knowingly relying" means you have
actual knowledge that, but for the patent license, your conveying the
covered work in a country, or your recipient's use of the covered work
in a country, would infringe one or more identifiable patents in that
country that you have reason to believe are valid.

  If, pursuant to or in connection with a single transaction or
arrangement, you convey, or propagate by procuring conveyance of, a
covered work, and grant a patent license to some of the parties
receiving the covered work authorizing them to use, propagate, modify
or convey a specific copy of the covered work, then the patent license
you grant is automatically extended to all recipients of the covered
work and works based on it.

  A patent license is "discriminatory" if it does not include within
the scope of its coverage, prohibits the exercise of, or is
conditioned on the non-exercise of one or more of the rights that are
specifically granted under this License.  You may not convey a covered
work if you are a party to an arrangement with a third party that is
in the business of distributing software, under which you make payment
to the third party based on the extent of your activity of conveying
the work, and under which the third party grants, to any of the
parties who would receive the covered work from you, a discriminatory
patent license (a) in connection with copies of the covered work
conveyed by you (or copies made from those copies), or (b) primarily
for and in connection with specific products or compilations that
contain the covered work, unless you entered into that arrangement,
or that patent license was granted, prior to 28 March 2007.

  Nothing in this License shall be construed as excluding or limiting
any implied license or other defenses to infringement that may
otherwise be available to you under applicable patent law.

  12. No Surrender of Others' Freedom.

  If conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot convey a
covered work so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you may
not convey it at all.  For example, if you agree to terms that obligate you
to collect a royalty for further conveying from those to whom you convey
the Program, the only way you could satisfy both those terms and this
License would be to refrain entirely from conveying the Program.

  13. Use with the GNU Affero General Public License.

  Notwithstanding any other provision of this License, you have
permission to link or combine any covered work with a work licensed
under version 3 of the GNU Affero General Public License into a single
combined work, and to convey the resulting work.  The terms of this
License will continue to apply to the part which is the covered work,
but the special requirements of the GNU Affero General Public License,
section 13, concerning interaction through a network will apply to the
combination as such.

  14. Revised Versions of this License.

  The Free Software Foundation may publish revised and/or new versions of
the GNU General Public License from time to time.  Such new versions will
be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

  Each version is given a distinguishing version number.  If the
Program specifies that a certain numbered version of the GNU General
Public License "or any later version" applies to it, you have the
option of following the terms and conditions either of that numbered
version or of any later version published by the Free Software
Foundation.  If the Program does not specify a version number of the
GNU General Public License, you may choose any version ever published
by the Free Software Foundation.

  If the Program specifies that a proxy can decide which future
versions of the GNU General Public License can be used, that proxy's
public statement of acceptance of a version permanently authorizes you
to choose that version for the Program.

  Later license versions may give you additional or different
permissions.  However, no additional obligations are imposed on any
author or copyright holder as a result of your choosing to follow a
later version.

  15. Disclaimer of Warranty.

  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

  16. Limitation of Liability.

  IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS
THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

  17. Interpretation of Sections 15 and 16.

  If the disclaimer of warranty and limitation of liability provided
above cannot be given local legal effect according to their terms,
reviewing courts shall apply local law that most closely approximates
an absolute waiver of all civil liability in connection with the
Program, unless a warranty or assumption of liability accompanies a
copy of the Program in return for a fee.

                     END OF TERMS AND CONDITIONS

"""#
