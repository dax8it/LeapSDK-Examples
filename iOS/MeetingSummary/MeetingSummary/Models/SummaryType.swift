

The dragged files copied but without content. Paste the codes below into each empty file, then build.

**ModelManager.swift:**
```swift
import LeapSDK

@MainActor
class ModelManager {
    @Published var state: ModelState = .notLoaded

    private var modelRunner: ModelRunner?

    func loadOrDownloadModel() async {
        guard modelRunner == nil else {
            state = .ready(cached: true)
            return
        }
        state = .downloading(progress: 0, downloadedBytes: 0, totalBytes: nil, bytesPerSecond: 0)
        var didReceiveProgressUpdate = false
        do {
            let runner = try await Leap.load(
                model: AppConfig.modelName,
                quantization: AppConfig.modelQuantizationQ4
            ) { progress in
                didReceiveProgressUpdate = true
                let bytesPerSecond: Int64
                if let maybeBytesPerSecond = progress.bytesPerSecond {
                    bytesPerSecond = maybeBytesPerSecond
                } else {
                    bytesPerSecond = 0
                }
                Task { @MainActor in
                    self.state = .downloading(
                        progress: progress.fractionCompleted,
                        downloadedBytes: progress.totalBytesDownloaded,
                        totalBytes: progress.totalBytesExpected,
                        bytesPerSecond: bytesPerSecond
                    )
                }
            }
            modelRunner = runner
            state = .ready(cached: !didReceiveProgressUpdate)
        } catch {
            state = .failed(message: "Failed to load model: \(error.localizedDescription)")
        }
    }

    func getRunner() throws -> ModelRunner {
        guard let runner = modelRunner else {
            throw ModelManagerError.runnerNotAvailable
        }
        return runner
    }
}

enum ModelManagerError: Error {
    case runnerNotAvailable
}
```

**SummarizerService.swift:**
```swift
import LeapSDK

class SummarizerService {
    private var currentGenerationHandler: GenerationHandler?

    func streamSummary(runner: ModelRunner, userContent: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            do {
                let conversation = try runner.createConversation(systemPrompt: AppConfig.systemPrompt)
                let generationOptions = GenerationOptions(temperature: AppConfig.temperature)
                let message = ChatMessage(role: .user, content: [ChatMessageContent.text(userContent)])
                let handler = conversation.generateResponse(message: message, generationOptions: generationOptions) { response in
                    switch response {
                    case .chunk(let text):
                        continuation.yield(text)
                    case .complete:
                        continuation.finish()
                    default:
                        break
                    }
                }
                self.currentGenerationHandler = handler
                if handler == nil {
                    continuation.finish(throwing: SummarizerError.generationFailed("Failed to start generation"))
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    func cancelGeneration() {
        currentGenerationHandler?.stop()
        currentGenerationHandler = nil
    }
}

enum SummarizerError: Error {
    case generationFailed(String)
}
```

**PromptBuilder.swift:**
```swift
struct PromptBuilder {
    static func build(summaryType: SummaryType, transcript: String) -> String {
        return summaryType.userPrompt + "\n\n" + transcript
    }

    static func templateTranscript() -> String {
        return """
        Alice: Good morning everyone. Let's start with the project update.

        Bob: I've completed the first phase of the development. The new feature is working as expected in our tests.

        Alice: Great, any issues we need to address?

        Bob: There was a minor bug with the UI, but it's fixed now. We'll need to update the documentation.

        Charlie: On the marketing side, we've seen a 20% increase in user engagement after the last campaign.

        Alice: Excellent. Let's schedule a follow-up meeting next week to review the rollout plan.

        Bob: Sounds good.
        """
    }
}
```

Check if [SummaryType.swift](cci:7://file:///Users/alexcovo/Documents/GITHUB/LeapSDK-Examples/iOS/meeting-summarizer/MeetingSummary/Models/SummaryType.swift:0:0-0:0) and [AppConfig.swift](cci:7://file:///Users/alexcovo/Documents/GITHUB/LeapSDK-Examples/iOS/meeting-summarizer/MeetingSummary/AppConfig.swift:0:0-0:0) are also empty—paste codes if needed. Build once populated. The app will then compile with full functionality. Share build result.

**Update TODO:** Populating all empty files.
