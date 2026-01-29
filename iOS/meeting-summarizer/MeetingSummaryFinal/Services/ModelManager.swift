import Foundation
import Leap

@MainActor
class ModelManager: ObservableObject {
    private let modelName = "LFM2-2.6B-Transcript"
    private let quantization = "Q4_K_M"
    
    @Published var modelRunner: ModelRunner?
    @Published var isModelLoaded = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadSpeed: Double = 0.0
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func loadModel() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            downloadProgress = 0.0
            downloadSpeed = 0.0
        }
        
        do {
            let runner = try await Leap.load(
                model: modelName,
                quantization: quantization
            ) { progress in
                Task { @MainActor in
                    self.downloadProgress = progress.fractionCompleted * 100
                    if let bytesPerSecond = progress.bytesPerSecond {
                        self.downloadSpeed = Double(bytesPerSecond)
                    }
                }
            }
            
            await MainActor.run {
                self.modelRunner = runner
                self.isModelLoaded = true
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load model: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    func unloadModel() {
        modelRunner = nil
        isModelLoaded = false
        errorMessage = nil
        downloadProgress = 0.0
        downloadSpeed = 0.0
    }
    
    func formatBytesPerSecond(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }
}