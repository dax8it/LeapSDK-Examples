import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MeetingSummaryViewModel()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                modelSection
                modelLoadedSection
                
                Spacer()
            }
            .padding()
            .navigationTitle("Meeting Summary")
            .alert("Error", isPresented: $viewModel.showingError) {
                Button("OK") { }
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
        }
    }

    @ViewBuilder
    private var modelSection: some View {
        switch viewModel.modelState {
        case .idle:
            modelDownloadSection(isDownloading: false, progress: 0, downloadedBytes: 0, totalBytes: nil, bytesPerSecond: 0)
        case .downloading(let progress, let downloadedBytes, let totalBytes, let bytesPerSecond):
            modelDownloadSection(isDownloading: true, progress: progress, downloadedBytes: downloadedBytes, totalBytes: totalBytes, bytesPerSecond: bytesPerSecond)
        case .ready(let cached):
            HStack {
                Text(cached ? "Model ready (cached)" : "Model ready")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text("Model")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                Button("Download Model") {
                    Task { await viewModel.downloadModel() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private func modelDownloadSection(
        isDownloading: Bool,
        progress: Double,
        downloadedBytes: Int64,
        totalBytes: Int64?,
        bytesPerSecond: Int64
    ) -> some View {
        VStack(spacing: 20) {
            Text("Download Model")
                .font(.headline)
            
            Text("\(viewModel.modelName) (\(viewModel.modelQuantization))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if isDownloading {
                VStack(spacing: 10) {
                    ProgressView(value: progress, total: 1)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let totalBytes {
                        Text("\(viewModel.formatBytes(downloadedBytes)) / \(viewModel.formatBytes(totalBytes))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(viewModel.formatBytes(downloadedBytes))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if bytesPerSecond > 0 {
                        Text(viewModel.formatBytesPerSecond(bytesPerSecond))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Button("Download Model") {
                    Task { await viewModel.downloadModel() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var modelLoadedSection: some View {
        VStack(spacing: 20) {
            summaryTypePicker
            
            transcriptSection
            
            actionButtons
            
            if viewModel.isGenerating {
                ProgressView("Generating summary…")
                    .padding()
            }

            if !viewModel.outputText.isEmpty {
                summarySection
            }
        }
    }
    
    private var summaryTypePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary Type")
                .font(.headline)
            
            Picker("Summary Type", selection: $viewModel.selectedSummaryType) {
                ForEach(SummaryType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }
    
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript")
                    .font(.headline)
                
                Spacer()
                
                Text("\(viewModel.transcript.count) chars")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Template") {
                    viewModel.insertTemplate()
                }
                .font(.caption)
            }
            
            TextEditor(text: $viewModel.transcript)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Generate Summary") {
                viewModel.generate()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isModelReady || viewModel.isGenerating || viewModel.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            
            if viewModel.isGenerating {
                Button("Cancel") {
                    viewModel.cancelGeneration()
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Summary")
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button("Copy") {
                        viewModel.copySummary()
                    }
                    .font(.caption)
                    
                    ShareLink(item: viewModel.outputText) {
                        Text("Share")
                            .font(.caption)
                    }
                }
            }
            
            ScrollView {
                Text(viewModel.outputText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}