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
