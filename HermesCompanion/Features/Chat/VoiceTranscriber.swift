import AVFoundation
import Speech

/// On-device speech recognition (SFSpeechRecognizer) — the transcribed text
/// lands in the composer as if typed. No backend change, no network needed.
@MainActor
final class VoiceTranscriber: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle

    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var onResult: ((String) -> Void)?

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    /// Ask for speech recognition authorization, then start recording.
    /// The final transcription is delivered once to `onResult`.
    func start(onResult: @escaping (String) -> Void) {
        guard self.onResult == nil else { return }
        self.onResult = onResult
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .authorized:
                    self.beginRecording()
                case .denied:
                    self.state = .unavailable("Speech recognition is disabled in Settings.")
                case .restricted:
                    self.state = .unavailable("Speech recognition is restricted on this device.")
                case .notDetermined:
                    self.state = .unavailable("Speech recognition authorization not granted.")
                @unknown default:
                    self.state = .unavailable("Speech recognition is unavailable.")
                }
            }
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        onResult = nil
        state = .idle
    }

    private func beginRecording() {
        // Device locale (nil = default); the recognizer picks the on-device
        // language model, so dictation works offline.
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            state = .unavailable("Speech recognition is not available on this device.")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .unavailable("Could not start the microphone: \(error.localizedDescription)")
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                if let result, result.isFinal, !result.bestTranscription.formattedString.isEmpty {
                    self.onResult?(result.bestTranscription.formattedString)
                }
                self.stop()
            }
        }

        let format = audioEngine.inputNode.outputFormat(forBus: 0)
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
            state = .recording
        } catch {
            state = .unavailable("Could not start the microphone: \(error.localizedDescription)")
            stop()
        }
    }
}
