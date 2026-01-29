import Foundation

enum AppConfig {
    static let modelName = "LFM2-2.6B-Transcript"
    static let modelQuantizationQ4 = "Q4_K_M"

    static let temperature: Float = 0.3

    static let systemPrompt = "You are an expert meeting analyst. Analyze the transcript carefully and provide clear, accurate information based on the content."
}

//
//  AppConfig.swift
//  MeetingSummary
//
//  Created by Alex Covo on 1/16/26.
//

