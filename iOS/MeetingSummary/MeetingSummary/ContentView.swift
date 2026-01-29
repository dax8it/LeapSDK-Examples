import SwiftUI
import Foundation

struct ContentView: View {
    @StateObject private var viewModel = MeetingSummaryViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Model Download Section
                    if case .downloading(let progress, let downloadedBytes, let totalBytes, let bytesPerSecond) = viewModel.modelState {
                        VStack(alignment: .leading) {
                            Text("Downloading Model...")
                                .font(.headline)
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                            Text(viewModel.modelDownloadProgressText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    } else if case .ready = viewModel.modelState {
                        Text("Model ready (cached)")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if case .failed = viewModel.modelState {
                        Text("Model download failed")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    // Transcript Section
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Meeting Transcript")
                                .font(.headline)
                            Spacer()
                            Button("Template") {
                                viewModel.insertTemplate()
                            }
                            .font(.caption)
                        }
                        TextEditor(text: $viewModel.transcript)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 200)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }

                    // Summary Type Picker
                    VStack(alignment: .leading) {
                        Text("Summary Type")
                            .font(.headline)
                        Picker("Summary Type", selection: $viewModel.selectedSummaryType) {
                            ForEach(SummaryType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Generate/Cancel Button
                    HStack {
                        if viewModel.isGenerating {
                            Button("Cancel") {
                                viewModel.cancelGeneration()
                            }
                            .foregroundColor(.red)
                        } else {
                            Button("Generate") {
                                viewModel.generate()
                            }
                            .disabled(!viewModel.isModelReady)
                        }
                        Spacer()
                    }
                    .buttonStyle(.borderedProminent)

                    // Output Section
                    if !viewModel.outputText.isEmpty || viewModel.isGenerating {
                        VStack(alignment: .leading) {
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
                .padding()
            }
            .navigationTitle("Meeting Summarizer")
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil), actions: {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        }, message: {
            Text(viewModel.errorMessage ?? "")
        })
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
