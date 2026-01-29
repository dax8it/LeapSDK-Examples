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