import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MeetingSummaryViewModel()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if !viewModel.isModelLoaded {
                    modelDownloadSection
                } else {
                    modelLoadedSection
                }
                
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
    
    private var modelDownloadSection: some View {
        VStack(spacing: 20) {
            Text("Download Model")
                .font(.headline)
            
            Text("LFM2-2.6B-Transcript (Q4_K_M)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if viewModel.isLoadingModel {
                VStack(spacing: 10) {
                    ProgressView(value: viewModel.downloadProgress, total: 100)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text("\(Int(viewModel.downloadProgress))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if viewModel.downloadSpeed != "0 B/s" {
                        Text(viewModel.downloadSpeed)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Button("Download Model") {
                    Task {
                        await viewModel.loadModel()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoadingModel)
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
                ProgressView("Generating summary...")
                    .padding()
            } else if !viewModel.summaryText.isEmpty {
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
                    Text(type.rawValue).tag(type)
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
                
                Button("Format Helper") {
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
                Task {
                    await viewModel.generateSummary()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isGenerating || viewModel.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            
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
                    
                    ShareLink(item: viewModel.summaryText) {
                        Text("Share")
                            .font(.caption)
                    }
                }
            }
            
            ScrollView {
                Text(viewModel.summaryText)
                    .font(.body)
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