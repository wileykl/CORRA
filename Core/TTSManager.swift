//
//  TTSManager.swift
//  CorraApp - Siri Text-to-Speech Integration
//

import Foundation
import Combine
import AVFoundation

class TTSManager: NSObject, ObservableObject {
    static let shared = TTSManager()
    
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var speechRate: Float = 0.5
    @Published var selectedVoice: AVSpeechSynthesisVoice?
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    
    override init() {
        super.init()
        setupSpeechSynthesizer()
        setupPreferredVoice()
    }
    
    private func setupSpeechSynthesizer() {
        speechSynthesizer.delegate = self
        
        // Configure audio session for speech
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            #if DEBUG
            print("❌ Failed to configure audio session: \(error)")
            #endif
        }
    }
    
    private func setupPreferredVoice() {
        // Use Samantha voice as preferred (from memory)
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // Look for Samantha first (user's preference)
        if let samantha = voices.first(where: { $0.name.lowercased().contains("samantha") }) {
            selectedVoice = samantha
        }
        // Fallback to high-quality US English voice
        else if let usEnglish = AVSpeechSynthesisVoice(language: "en-US") {
            selectedVoice = usEnglish
        }
        // Final fallback to system default
        else {
            selectedVoice = AVSpeechSynthesisVoice(language: "en")
        }
    }
    
    // MARK: - Public TTS Methods
    
    func speak(text: String) {
        guard !text.isEmpty else { return }
        
        // Stop any current speech
        stop()
        
        // Clean text for better speech (remove markdown, emojis, etc.)
        let cleanText = cleanTextForSpeech(text)
        
        // Create utterance
        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.voice = selectedVoice
        utterance.rate = speechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        currentUtterance = utterance
        speechSynthesizer.speak(utterance)
    }
    
    func pause() {
        guard isSpeaking && !isPaused else { return }
        speechSynthesizer.pauseSpeaking(at: .immediate)
        isPaused = true
    }
    
    func resume() {
        guard isPaused else { return }
        speechSynthesizer.continueSpeaking()
        isPaused = false
    }
    
    func stop() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        currentUtterance = nil
        isSpeaking = false
        isPaused = false
    }
    
    // MARK: - Text Cleaning
    
    private func cleanTextForSpeech(_ text: String) -> String {
        var cleanText = text
        
        // Remove markdown formatting
        cleanText = cleanText.replacingOccurrences(of: "**", with: "")
        cleanText = cleanText.replacingOccurrences(of: "*", with: "")
        cleanText = cleanText.replacingOccurrences(of: "#", with: "")
        
        // Remove emoji and special symbols
        cleanText = cleanText.replacingOccurrences(of: "✅", with: "")
        cleanText = cleanText.replacingOccurrences(of: "❌", with: "")
        cleanText = cleanText.replacingOccurrences(of: "⚠️", with: "Warning:")
        cleanText = cleanText.replacingOccurrences(of: "🎯", with: "")
        cleanText = cleanText.replacingOccurrences(of: "🔍", with: "")
        
        // Improve pronunciation of medical terms
        cleanText = cleanText.replacingOccurrences(of: "FDA", with: "F D A")
        cleanText = cleanText.replacingOccurrences(of: "NIH", with: "N I H")
        cleanText = cleanText.replacingOccurrences(of: "IRB", with: "I R B")
        cleanText = cleanText.replacingOccurrences(of: "vs.", with: "versus")
        cleanText = cleanText.replacingOccurrences(of: "e.g.", with: "for example")
        cleanText = cleanText.replacingOccurrences(of: "i.e.", with: "that is")
        
        // Clean up extra whitespace
        cleanText = cleanText.replacingOccurrences(of: "\n", with: " ")
        cleanText = cleanText.replacingOccurrences(of: "  ", with: " ")
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleanText
    }
    
    // MARK: - Voice Selection
    
    func getAvailableVoices() -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
    }
    
    func setVoice(_ voice: AVSpeechSynthesisVoice) {
        selectedVoice = voice
    }
    
    func setSpeechRate(_ rate: Float) {
        speechRate = max(0.1, min(1.0, rate))
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
            self.isPaused = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.isPaused = false
            self.currentUtterance = nil
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPaused = true
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPaused = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.isPaused = false
            self.currentUtterance = nil
        }
    }
}
