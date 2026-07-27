import SwiftUI
import PencilKit
import UIKit
import Photos

struct ContentView: View {

    // MARK: - Input mode

    private enum InputMode: String {
        case pencil = "Pencil"
        case finger = "Finger"
    }

    @State private var selectedInputMode: InputMode? = nil

    // MARK: - Drawing and results

    @State private var drawing = PKDrawing()
    @State private var metrics: TraceMetrics? = nil

    @State private var toastText: String? = nil
    @State private var exportURLs: [URL] = []
    @State private var showShareSheet = false

    @State private var hasStartedDrawing = false
    @State private var isPlayingDemo = true
    @State private var demoProgress: CGFloat = 0
    @State private var showBeginText = false

    @State private var demoTimer: Timer? = nil

//    @StateObject private var cameraManager = CameraManager()

    // MARK: - Spiral parameters

    private let turns: CGFloat = 3
    private let a: CGFloat = 8
    private let margin: CGFloat = 24

    // MARK: - Demo timing

    private let demoDuration: Double = 3.0
    private let beginDisplayDuration: Double = 2.0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(
                x: size.width / 2,
                y: size.height / 2
            )

            let maxR = min(size.width, size.height) / 2 - margin
            let thetaMax = 2 * CGFloat.pi * turns
            let b = max(1, (maxR - a) / thetaMax)

            ZStack {
                Color.white
                    .ignoresSafeArea()

                SpiralView(
                    turns: turns,
                    a: a,
                    margin: margin
                )

                if isPlayingDemo {
                    SpiralDemoOverlay(
                        turns: turns,
                        a: a,
                        margin: margin,
                        progress: demoProgress
                    )
                }

                if showBeginText &&
                    !hasStartedDrawing &&
                    selectedInputMode != nil {

                    Text("Begin")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 16)
                        )
                        .allowsHitTesting(false)
                }

                /*
                 The canvas still accepts any input exactly as before.

                 Selecting Pencil or Finger only records the intended
                 input mode. It does not change the drawing behavior or
                 scoring calculations.
                 */
                PencilCanvasView(
                    drawing: $drawing,
                    hasStartedDrawing: $hasStartedDrawing,
                    isEnabled: !isPlayingDemo &&
                               selectedInputMode != nil,
                    onFirstInput: {
                        showBeginText = false
                    }
                )

                // Prompt shown after demo until a mode is selected
                if !isPlayingDemo &&
                    selectedInputMode == nil &&
                    !hasStartedDrawing {

                    VStack(spacing: 10) {
                        Text("Select Input Mode")
                            .font(.title2)
                            .bold()

                        Text("Choose Pencil or Finger above to begin.")
                            .font(.body)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                    .background(.ultraThinMaterial)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 16)
                    )
                    .allowsHitTesting(false)
                }

                // Bottom overlays
                VStack {
                    Spacer()

                    if let currentMetrics = metrics,
                       let inputMode = selectedInputMode {

                        MetricsPanel(
                            metrics: currentMetrics,
                            inputMode: inputMode.rawValue
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }

                    if let toastText {
                        Text(toastText)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(
                                RoundedRectangle(cornerRadius: 12)
                            )
                            .padding(.bottom, 16)
                            .transition(.opacity)
                    }
                }
                .allowsHitTesting(false)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                ScrollView(
                    .horizontal,
                    showsIndicators: false
                ) {
                    HStack(spacing: 10) {

                        // MARK: Mode selector

                        Menu {
                            Button("Pencil") {
                                selectMode(.pencil)
                            }

                            Button("Finger") {
                                selectMode(.finger)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text("Mode:")

                                Text(
                                    selectedInputMode?.rawValue ??
                                    "Select"
                                )
                                .bold()

                                Image(
                                    systemName:
                                        "chevron.down"
                                )
                                .font(.caption)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            isPlayingDemo ||
                            hasStartedDrawing
                        )

                        Button("Reset") {
                            resetAssessment()
                        }
                        .buttonStyle(.borderedProminent)

//                        Button {
//                            if cameraManager.isRecording {
//                                cameraManager.stopRecording {
//                                    url,
//                                    error in
//
//                                    if let url {
//                                        saveVideoToPhotos(
//                                            url: url
//                                        )
//                                    } else if let error {
//                                        print(
//                                            "Recording error:",
//                                            error
//                                        )
//                                        showToast(
//                                            "Video failed"
//                                        )
//                                    }
//                                }
//                            } else {
//                                cameraManager.startRecording()
//                            }
//                        } label: {
//                            Text(
//                                cameraManager.isRecording
//                                    ? "Stop Recording"
//                                    : "Start video record"
//                            )
//                            .fixedSize()
//                        }
//                        .buttonStyle(.bordered)
//                        .tint(
//                            cameraManager.isRecording
//                                ? .red
//                                : .blue
//                        )

                        Button("Replay Demo") {
                            replayDemo()
                        }
                        .buttonStyle(.bordered)

                        Button("Score") {
                            guard let inputMode =
                                    selectedInputMode else {
                                showToast(
                                    "Select Pencil or Finger"
                                )
                                return
                            }

                            metrics = ScoringEngine.score(
                                drawing: drawing,
                                canvasSize: size,
                                center: center,
                                a: a,
                                b: b,
                                turns: turns,
                                margin: margin
                            )

                            showToast(
                                "Scored as \(inputMode.rawValue) ✅"
                            )
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            selectedInputMode == nil ||
                            drawing.strokes.isEmpty
                        )

                        Button("Copy Results") {
                            guard let currentMetrics = metrics,
                                  let inputMode =
                                    selectedInputMode else {
                                return
                            }

                            UIPasteboard.general.string =
                                resultsText(
                                    metrics: currentMetrics,
                                    inputMode: inputMode
                                )

                            showToast("Copied ✅")
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            metrics == nil ||
                            selectedInputMode == nil
                        )

                        Button("Export") {
                            guard let currentMetrics = metrics,
                                  let inputMode =
                                    selectedInputMode else {
                                return
                            }

                            do {
                                let scale =
                                    (
                                        UIApplication.shared
                                            .connectedScenes
                                            .first
                                        as? UIWindowScene
                                    )?
                                    .screen
                                    .nativeScale
                                    ??
                                    UIScreen.main.nativeScale

                                exportURLs =
                                    try SessionSaver.saveSession(
                                        metricsText:
                                            resultsText(
                                                metrics:
                                                    currentMetrics,
                                                inputMode:
                                                    inputMode
                                            ),
                                        drawing: drawing,
                                        scale: scale
                                    )

                                showShareSheet = true
                            } catch {
                                print(
                                    "Export failed:",
                                    error
                                )
                                showToast("Export failed")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            metrics == nil ||
                            selectedInputMode == nil
                        )
                    }
                    .padding(.leading, 16)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color.white)
            }
        }
        .sheet(
            isPresented: $showShareSheet,
            onDismiss: {
                DispatchQueue.main.async {
                    if !exportURLs.isEmpty {
                        SessionSaver.cleanup(
                            exportURLs
                        )
                        exportURLs = []
                    }
                }
            }
        ) {
            ShareSheet(
                items: exportURLs,
                onComplete: {
                    DispatchQueue.main.async {
                        SessionSaver.cleanup(
                            exportURLs
                        )
                        exportURLs = []
                        showToast("Exported ✅")
                    }
                }
            )
        }
        .onAppear {
            startDemo()
//            cameraManager.configure()
        }
        .onDisappear {
            demoTimer?.invalidate()
            demoTimer = nil
        }
    }

    // MARK: - Mode selection

    private func selectMode(_ mode: InputMode) {
        guard !hasStartedDrawing else {
            showToast(
                "Reset before changing mode"
            )
            return
        }

        selectedInputMode = mode
        metrics = nil

        if !isPlayingDemo {
            showBeginPrompt()
        }

        showToast(
            "\(mode.rawValue) selected"
        )
    }

    private func showBeginPrompt() {
        showBeginText = true

        DispatchQueue.main.asyncAfter(
            deadline: .now() + beginDisplayDuration
        ) {
            if !hasStartedDrawing {
                showBeginText = false
            }
        }
    }

    // MARK: - Results text

    private func resultsText(
        metrics: TraceMetrics,
        inputMode: InputMode
    ) -> String {
        """
        Input Mode: \(inputMode.rawValue)

        \(metrics.asCopyText())
        """
    }

    // MARK: - Reset

    private func resetAssessment() {
        drawing = PKDrawing()
        metrics = nil
        hasStartedDrawing = false
        selectedInputMode = nil
        showBeginText = false

        showToast(
            "Reset — select input mode"
        )
    }

    // MARK: - Video

    private func saveVideoToPhotos(url: URL) {
        PHPhotoLibrary.requestAuthorization(
            for: .addOnly
        ) { status in
            guard status == .authorized ||
                  status == .limited else {
                DispatchQueue.main.async {
                    showToast(
                        "Photo access not allowed"
                    )
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest
                    .creationRequestForAssetFromVideo(
                        atFileURL: url
                    )
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        showToast("Video saved ✅")
                    } else {
                        print(
                            "Video save error:",
                            error as Any
                        )
                        showToast("Save failed")
                    }
                }

                try? FileManager.default
                    .removeItem(at: url)
            }
        }
    }

    // MARK: - Demo

    private func startDemo() {
        demoTimer?.invalidate()
        demoTimer = nil

        isPlayingDemo = true
        showBeginText = false
        hasStartedDrawing = false
        demoProgress = 0

        let startTime = Date()

        demoTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 60.0,
            repeats: true
        ) { timer in
            let elapsed =
                Date().timeIntervalSince(startTime)

            let progress =
                min(
                    elapsed / demoDuration,
                    1.0
                )

            demoProgress = CGFloat(progress)

            if progress >= 1.0 {
                timer.invalidate()
                demoTimer = nil
                isPlayingDemo = false

                /*
                 Do not show Begin until the examiner
                 selects Pencil or Finger.
                 */
                if selectedInputMode != nil {
                    showBeginPrompt()
                }
            }
        }
    }

    private func replayDemo() {
        drawing = PKDrawing()
        metrics = nil
        hasStartedDrawing = false
        selectedInputMode = nil
        startDemo()
    }

    // MARK: - Toast

    private func showToast(_ text: String) {
        withAnimation {
            toastText = text
        }

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1.2
        ) {
            withAnimation {
                toastText = nil
            }
        }
    }
}

#Preview {
    ContentView()
}
