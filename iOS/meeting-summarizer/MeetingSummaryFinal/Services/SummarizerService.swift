import Foundation
import Leap

class SummarizerService {
    private let systemPrompt = "You are an expert meeting analyst. Analyze the transcript carefully and provide clear, accurate information based on the content."
    private let temperature: Float = 0.3
    
    private var modelRunner: ModelRunner?
    private var currentConversation: Conversation?
    
    init(modelRunner: ModelRunner?) {
        self.modelRunner = modelRunner
    }
    
    func updateModelRunner(_ modelRunner: ModelRunner?) {
        self.modelRunner = modelRunner
        currentConversation = nil
    }
    
    func generateSummary(summaryType: SummaryType, transcript: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let modelRunner = modelRunner else {
            throw SummarizerError.modelNotLoaded
        }
        
        let prompt = PromptBuilder.buildPrompt(summaryType: summaryType, transcript: transcript)
        
        let conversation = try modelRunner.createConversation(systemPrompt: systemPrompt)
        self.currentConversation = conversation
        
        let generationOptions = GenerationOptions(
            temperature: temperature
        )
        
        return try conversation.generateResponse(
            message: prompt,
            generationOptions: generationOptions
        )
    }
    
    func cancelGeneration() {
        currentConversation = nil
    }
}

enum SummarizerError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Model is not loaded. Please download and load the model first."
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        }
    }
}