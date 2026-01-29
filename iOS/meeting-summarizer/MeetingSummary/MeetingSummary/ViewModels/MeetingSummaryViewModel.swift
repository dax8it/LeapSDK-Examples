import SwiftUI
import LeapSDK

@MainActor
class MeetingSummaryViewModel: ObservableObject {
    @Published var transcript: String = ""
    @Published var selectedSummaryType: SummaryType = .brief
    @Published var outputText: String = ""
    @Published var isGenerating: Bool = false
    @Published var errorMessage: String?
    @Published var modelState: ModelState = .notLoaded

    private let modelManager = ModelManager()
    private let summarizerService = SummarizerService()
    private var generationTask: Task<Void, Never>?

    var isModelReady: Bool {
        if case .ready = modelState { return true }
        return false
    }

    var modelDownloadProgressText: String {
        switch modelState {
        case .downloading(progress: let progress, downloadedBytes: let downloaded, totalBytes: let total, bytesPerSecond: let speed):
            let percent = Int(progress * 100)
            let downloadedMB = ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)
            let totalMB = total.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "?"
            let speedMBps = ByteCountFormatter.string(fromByteCount: speed, countStyle: .file) + "/s"
            return "\(percent)% (\(downloadedMB) / \(totalMB), \(speedMBps))"
        default:
            return ""
        }
    }

    func downloadModel() async {
        await modelManager.loadOrDownloadModel()
        modelState = modelManager.state
    }

    func generate() {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError("Please enter a transcript before generating a summary.")
            return
        }
        guard isModelReady else {
            showError("Please download the model first.")
            return
        }
        generationTask?.cancel()
        summarizerService.cancelGeneration()
        isGenerating = true
        outputText = ""
        errorMessage = nil
        let transcript = transcript
        let selectedSummaryType = selectedSummaryType
        generationTask = Task {
            do {
                let runner = try self.modelManager.getRunner()
                let userContent = PromptBuilder.build(summaryType: selectedSummaryType, transcript: transcript)
                let stream = self.summarizerService.streamSummary(runner: runner, userContent: userContent)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        self.outputText += chunk
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.showError("Failed to generate summary: \(error.localizedDescription)")
                        self.outputText = ""
                    }
                }
            }
            await MainActor.run {
                self.isGenerating = false
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        summarizerService.cancelGeneration()
        isGenerating = false
    }

    func insertTemplate() {
        transcript = PromptBuilder.templateTranscript()
    }

    func copySummary() {
        UIPasteboard.general.string = outputText
    }

    private func showError(_ message: String) {
        errorMessage = message
    }
}

enum ModelState {
    case notLoaded
    case downloading(progress: Double, downloadedBytes: Int64, totalBytes: Int64?, bytesPerSecond: Int64)
    case ready(cached: Bool)
    case failed(message: String)
}