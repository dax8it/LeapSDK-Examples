import Foundation
import SwiftUI

@MainActor
class MeetingSummaryViewModel: ObservableObject {
    @Published var transcript = ""
    @Published var summaryText = ""
    @Published var selectedSummaryType: SummaryType = .detailed
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var showingError = false
    
    private let modelManager = ModelManager()
    private var summarizerService: SummarizerService
    
    init() {
        self.summarizerService = SummarizerService(modelRunner: nil)
    }
    
    var isModelLoaded: Bool {
        modelManager.isModelLoaded
    }
    
    var isLoadingModel: Bool {
        modelManager.isLoading
    }
    
    var downloadProgress: Double {
        modelManager.downloadProgress
    }
    
    var downloadSpeed: String {
        modelManager.formatBytesPerSecond(modelManager.downloadSpeed)
    }
    
    func loadModel() async {
        await modelManager.loadModel()
        summarizerService.updateModelRunner(modelManager.modelRunner)
        
        if let error = modelManager.errorMessage {
            showError(error)
        }
    }
    
    func unloadModel() {
        modelManager.unloadModel()
        summarizerService.updateModelRunner(nil)
    }
    
    func generateSummary() async {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError("Please enter a transcript before generating a summary.")
            return
        }
        
        guard isModelLoaded else {
            showError("Please download and load the model first.")
            return
        }
        
        await MainActor.run {
            isGenerating = true
            summaryText = ""
            errorMessage = nil
        }
        
        do {
            let stream = try await summarizerService.generateSummary(
                summaryType: selectedSummaryType,
                transcript: transcript
            )
            
            for try await chunk in stream {
                await MainActor.run {
                    summaryText += chunk
                }
            }
        } catch {
            await MainActor.run {
                showError("Failed to generate summary: \(error.localizedDescription)")
                summaryText = ""
            }
        }
        
        await MainActor.run {
            isGenerating = false
        }
    }
    
    func cancelGeneration() {
        summarizerService.cancelGeneration()
        isGenerating = false
    }
    
    func insertTemplate() {
        transcript = PromptBuilder.createTemplateTranscript()
    }
    
    func copySummary() {
        UIPasteboard.general.string = summaryText
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}