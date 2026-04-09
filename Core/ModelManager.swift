//
//  ModelManager.swift
//  Corra Clinical Trials Assistant
//
//  Manages the LLaMA model loading and inference with safety boundaries
//

import Foundation
import AVFoundation
import Combine

class ModelManager: NSObject, ObservableObject {
    static let shared = ModelManager()
    
    @Published var isModelLoaded = false
    @Published var loadingProgress: Float = 0.0
    @Published var currentResponse = ""
    @Published var isGenerating = false
    @Published var errorMessage = ""
    @Published var streamingResponse = "" // Real-time streaming response
    // Note: Removed shouldSpeakResponse - TTS is now manual activation only
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var speechRate: Float = 0.52 // Speech speed (0.0 - 1.0) - balanced speed for natural flow
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedVoiceIndex: Int = 0
    
    // Real-time TTS tracking for chunk-based speech
    private var lastSpokenLength = 0
    private var isRealTimeTTSActive = false
    private var currentStreamingText = ""
    
    private var bridge: LlamaCppBridge?
    private let safetyBoundaries = SafetyBoundaries.shared
    private let memoryManager = MemoryManager.shared
    private let cagManager = CAGManager.shared
    
    // TTS functionality
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var selectedVoice: AVSpeechSynthesisVoice?
    private var streamingCompletion: ((String) -> Void)?
    private var lastStreamingUserPrompt: String = ""  // For safety filterResponse(query) when streaming completes
    
    override private init() {
        super.init()
        setupTTS()
    }
    
    deinit {
        // Clean up bridge
        bridge?.unloadModel()
        bridge = nil
    }
    
    func loadModel() {
        #if DEBUG
        print("[Model] Starting model load...")
        #endif
        
        // Reset error message
        DispatchQueue.main.async {
            self.errorMessage = ""
        }
        
        // Only use the CAG model - no fallback
        // Try multiple methods to find the model file
        var modelPath: String?
        
        // Method 1: Bundle.main.path (standard method)
        if let path = Bundle.main.path(forResource: "Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103", ofType: "gguf") {
            modelPath = path
        } else {
            // Method 2: Bundle.main.url (alternative method)
            if let url = Bundle.main.url(forResource: "Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103", withExtension: "gguf") {
                modelPath = url.path
            } else {
                // Method 3: Direct path in bundle root
                let bundlePath = Bundle.main.bundlePath
                let directPath = "\(bundlePath)/Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103.gguf"
                
                if FileManager.default.fileExists(atPath: directPath) {
                    modelPath = directPath
                } else {
                    // Method 4: Resource path
                    let resourcePath = Bundle.main.resourcePath ?? ""
                    let resourceFullPath = "\(resourcePath)/Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103.gguf"
                    
                    if FileManager.default.fileExists(atPath: resourceFullPath) {
                        modelPath = resourceFullPath
                    }
                }
            }
        }
        
        guard let finalPath = modelPath else {
            let errorMsg = "Model file not found in app bundle.\n\nExpected: Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103.gguf\n\nTried multiple search methods. Please verify the file is in 'Copy Bundle Resources'."
            DispatchQueue.main.async {
                self.errorMessage = errorMsg
                self.loadingProgress = 0.0
            }
            return
        }
        
        loadModelAtPath(finalPath)
    }
    
    func loadModelWithReducedConfig() {
        #if DEBUG
        print("[Model] WARNING: Loading CAG model with reduced configuration due to memory constraints")
        #endif
        
        // Use same path-finding logic as loadModel()
        var modelPath: String?
        
        if let path = Bundle.main.path(forResource: "Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103", ofType: "gguf") {
            modelPath = path
        } else if let url = Bundle.main.url(forResource: "Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103", withExtension: "gguf") {
            modelPath = url.path
        } else {
            let bundlePath = Bundle.main.bundlePath
            let directPath = "\(bundlePath)/Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103.gguf"
            if FileManager.default.fileExists(atPath: directPath) {
                modelPath = directPath
            } else {
                let resourcePath = Bundle.main.resourcePath ?? ""
                let resourceFullPath = "\(resourcePath)/Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103.gguf"
                if FileManager.default.fileExists(atPath: resourceFullPath) {
                    modelPath = resourceFullPath
                }
            }
        }
        
        guard let finalPath = modelPath else {
            errorMessage = "CAG model file not found. Expected: Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103.gguf"
            #if DEBUG
            print("[Model] ERROR: CAG model file not found")
            #endif
            return
        }
        
        let config = memoryManager.getRecommendedConfiguration()
        loadModelAtPath(finalPath, configuration: config)
    }
    
    private func loadModelAtPath(_ path: String, configuration: ModelConfiguration? = nil) {
        #if DEBUG
        print("[Model] Loading model...")
        #endif
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Create bridge with configuration
            let config = configuration ?? self.memoryManager.getRecommendedConfiguration()
            #if DEBUG
            print("📊 Using config - Context: \(config.contextSize), GPU Layers: \(config.gpuLayers), MLock: \(config.useMlock)")
            #endif
            
            // CRITICAL FIX: Initialize bridge differently to handle CPU backend issue
            self.bridge = LlamaCppBridge(modelPath: path)
            
            #if DEBUG
            print("🔗 Bridge created, attempting to load model...")
            #endif
            
            // Set system prompt from safety boundaries
            self.bridge?.setSystemPrompt(self.safetyBoundaries.getSystemPrompt())
            
            // Set up streaming delegate
            self.bridge?.streamingDelegate = self
            
            // Load the model
            do {
                try self.bridge?.loadModel()
                DispatchQueue.main.async {
                    self.isModelLoaded = true
                    self.loadingProgress = 1.0
                    #if DEBUG
                    print("✅ Model loaded successfully")
                    #endif
                }
            } catch {
                DispatchQueue.main.async {
                    self.isModelLoaded = false
                    self.loadingProgress = 0.0
                    self.errorMessage = "Failed to load model: \(error.localizedDescription)"
                    #if DEBUG
                    print("❌ Model loading failed: \(error)")
                    #endif
                }
            }
        }
    }
    
    @MainActor
    func unloadModel() {
        bridge?.unloadModel()
        bridge = nil
        isModelLoaded = false
        loadingProgress = 0.0
        currentResponse = ""
        isGenerating = false
    }
    
    func generateResponse(for prompt: String) async -> String {
        guard isModelLoaded, let bridge = bridge else {
            return "Model is not loaded. Please wait for the model to finish loading."
        }
        
        // Apply safety boundaries
        let validation = safetyBoundaries.validateInput(prompt)
        guard validation.isValid else {
            return "I can only help with clinical trial and medical research questions. Please ask about topics related to clinical trials, medical studies, or healthcare research."
        }
        
        // Build CAG-enhanced prompt
        let cagPrompt = cagManager.buildCAGPrompt(userQuestion: prompt)
        
        await MainActor.run {
            isGenerating = true
            currentResponse = ""
        }
        
            let response = await withTaskGroup(of: String.self) { group in
                group.addTask {
                    return bridge.generateResponse(
                        forPrompt: cagPrompt,
                        maxTokens: 2048, // Removed artificial limit - rely on streaming control and natural stopping
                        temperature: 0.7
                    )
                }
            
            // Add timeout
            group.addTask {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                return "Response timed out. Please try a shorter question."
            }
            
            return await group.first { _ in true } ?? "Failed to generate response"
        }
        
        await MainActor.run {
            isGenerating = false
        }
        
        // Apply safety filtering to response
        let safeResponse = safetyBoundaries.filterResponse(response, for: prompt)
        
        await MainActor.run {
            currentResponse = safeResponse
        }
        
        return safeResponse
    }
    
    // STREAMING GENERATION: Real-time token delivery
    func generateStreamingResponse(for prompt: String, completion: @escaping (String) -> Void) {
        guard isModelLoaded, let bridge = bridge else {
            completion("Model is not loaded. Please wait for the model to finish loading.")
            return
        }
        
        // Apply safety boundaries
        let validation = safetyBoundaries.validateInput(prompt)
        guard validation.isValid else {
            completion("I can only help with clinical trial and medical research questions. Please ask about topics related to clinical trials, medical studies, or healthcare research.")
            return
        }
        
        // Check memory before generating
        if memoryManager.memoryPressure == .critical {
            completion("Memory is critically low. Please close other apps and try again.")
            return
        }
        
        // Build CAG-enhanced prompt
        let cagPrompt = cagManager.buildCAGPrompt(userQuestion: prompt)
        lastStreamingUserPrompt = prompt  // So filterResponse can use query for language filtering
        
        // Set up for streaming
        DispatchQueue.main.async {
            self.isGenerating = true
            self.streamingResponse = ""
            
            // MANUAL TTS: Do not auto-activate TTS - user controls via speech button
            self.lastSpokenLength = 0
            self.isRealTimeTTSActive = false // Always false - manual activation only
            self.currentStreamingText = ""
        }
        
        // Store completion handler
        self.streamingCompletion = completion
        
        // Start streaming generation on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            bridge.generateStreamingResponse(forPrompt: cagPrompt, maxTokens: 2048, temperature: 0.7) // Removed artificial limit - rely on streaming control
        }
    }
    
    func stopGeneration() {
        // Set stop flag for streaming generation
        DispatchQueue.main.async {
            self.isGenerating = false
        }
    }
    
    func getModelInfo() -> [String: Any] {
        guard bridge != nil else {
            return ["error": "Model not loaded"]
        }
        
        // Note: getModelInfo method doesn't exist in current bridge
        return ["status": "Model loaded", "backend": "LlamaCpp"]
    }
    
    func getCurrentMemoryUsage() -> Int {
        return bridge?.getCurrentMemoryUsage() ?? 0
    }
    
    func reduceMemoryFootprint() {
        bridge?.reduceMemoryFootprint()
    }
}

// MARK: - LlamaCppBridgeStreamingDelegate
extension ModelManager: LlamaCppBridgeStreamingDelegate {
    func llamaBridge(_ bridge: LlamaCppBridge, didGenerateToken token: String, partialResponse: String) {
        // Update streaming response in real-time
        DispatchQueue.main.async {
            self.streamingResponse = partialResponse
            // Note: No automatic TTS - user controls speech manually via button
        }
    }
    
    func llamaBridge(_ bridge: LlamaCppBridge, didCompleteWithResponse finalResponse: String) {
        // Apply safety filtering to final response (use stored user prompt for language filtering)
        let safeResponse = safetyBoundaries.filterResponse(finalResponse, for: lastStreamingUserPrompt)
        
        DispatchQueue.main.async {
            self.isGenerating = false
            self.currentResponse = safeResponse
            self.streamingResponse = safeResponse
            
            // MANUAL TTS: No automatic speech - user controls via speech button
            // Reset TTS tracking
            self.isRealTimeTTSActive = false
            self.lastSpokenLength = 0
        }
        
        // Call completion handler
        streamingCompletion?(safeResponse)
        streamingCompletion = nil
    }
}

// MARK: - TTS Functionality
extension ModelManager {
    private func setupTTS() {
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
        
        // Set up preferred voice (Samantha from memory)
        setupPreferredVoice()
    }
    
    private func setupPreferredVoice() {
        // Get all available English voices (including Personal Voice and Enhanced)
        availableVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { 
                // Sort by quality: Personal Voice > Enhanced > Premium > Default
                if $0.quality != $1.quality {
                    return $0.quality.rawValue > $1.quality.rawValue
                }
                return $0.name < $1.name
            }
        
        #if DEBUG
        print("🎙️ Available voices by quality (searching for Siri-like voices):")
        for (index, voice) in availableVoices.enumerated() {
            let qualityName = getQualityName(voice.quality)
            print("  \(index): \(voice.name) (\(voice.language)) - Quality: \(qualityName)")
        }
        #endif
        
        // PRIORITY 1: Look for Personal Voice (iOS 17+) - Most natural, Siri-like
        if #available(iOS 17.0, *) {
            if let personalVoiceIndex = availableVoices.firstIndex(where: { 
                $0.quality == .premium && // Personal Voice often shows as premium
                ($0.name.lowercased().contains("personal") || 
                 $0.name.lowercased().contains("voice") ||
                 $0.identifier.contains("personal"))
            }) {
                selectedVoiceIndex = personalVoiceIndex
                selectedVoice = availableVoices[personalVoiceIndex]
                #if DEBUG
                print("🎙️ 🌟 Using PERSONAL VOICE - Most Natural (Siri-like)!")
                #endif
                return
            }
        }
        
        // PRIORITY 2: Look for Enhanced Samantha (closest to Siri)
        if let enhancedSamanthaIndex = availableVoices.firstIndex(where: { 
            $0.name.lowercased().contains("samantha") && 
            $0.language == "en-US" && 
            $0.quality == .enhanced
        }) {
            selectedVoiceIndex = enhancedSamanthaIndex
            selectedVoice = availableVoices[enhancedSamanthaIndex]
            #if DEBUG
            print("🎙️ ✅ Using ENHANCED Samantha - Siri-like Quality!")
            #endif
            return
        }
        
        // PRIORITY 3: Look for ANY Enhanced US English voice (better than basic)
        if let enhancedUSIndex = availableVoices.firstIndex(where: { 
            $0.language == "en-US" && $0.quality == .enhanced
        }) {
            selectedVoiceIndex = enhancedUSIndex
            selectedVoice = availableVoices[enhancedUSIndex]
            #if DEBUG
            print("🎙️ ✅ Using Enhanced US English voice: \(availableVoices[enhancedUSIndex].name) - Better than basic TTS")
            #endif
            return
        }
        
        // PRIORITY 4: Look for Premium quality voices
        if let premiumUSIndex = availableVoices.firstIndex(where: { 
            $0.language == "en-US" && $0.quality == .premium
        }) {
            selectedVoiceIndex = premiumUSIndex
            selectedVoice = availableVoices[premiumUSIndex]
            #if DEBUG
            print("🎙️ ✅ Using Premium US English voice: \(availableVoices[premiumUSIndex].name)")
            #endif
            return
        }
        
        // FALLBACK: Regular Samantha (last resort)
        if let samanthaIndex = availableVoices.firstIndex(where: { 
            $0.name.lowercased().contains("samantha") && $0.language == "en-US" 
        }) {
            selectedVoiceIndex = samanthaIndex
            selectedVoice = availableVoices[samanthaIndex]
            #if DEBUG
            print("🎙️ ⚠️ Using Standard Samantha")
            #endif
            return
        }
        // Fallback to high-quality US English voice
        else if let usEnglishIndex = availableVoices.firstIndex(where: { $0.language == "en-US" }) {
            selectedVoiceIndex = usEnglishIndex
            selectedVoice = availableVoices[usEnglishIndex]
        }
        // Final fallback to first available voice
        else if !availableVoices.isEmpty {
            selectedVoiceIndex = 0
            selectedVoice = availableVoices[0]
        }
        
        #if DEBUG
        print("🎙️ Available voices: \(availableVoices.count)")
        #endif
    }
    
    func speak(text: String) {
        guard !text.isEmpty else { return }
        
        // Stop any current speech
        stopSpeech()
        
        // Clean text for better speech
        let cleanText = cleanTextForSpeech(text)
        
        // Create utterance with enhanced natural voice settings
        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.voice = availableVoices.isEmpty ? nil : availableVoices[selectedVoiceIndex]
        
        // BALANCED SPEED: Match chunk TTS for consistency
        utterance.rate = speechRate * 0.95 // Balanced rate matching chunk TTS
        utterance.pitchMultiplier = 0.96 // Slightly higher pitch for clarity
        utterance.volume = 0.9 // Slightly lower volume to reduce harshness
        
        // Balanced timing settings
        utterance.preUtteranceDelay = 0.15 // Shorter pause before speaking
        utterance.postUtteranceDelay = 0.2 // Shorter pause after speaking
        
        // Voice-specific optimizations for maximum naturalness
        if let voice = utterance.voice {
            // Balanced settings for different voice qualities
            switch voice.quality {
            case .enhanced:
                utterance.rate = speechRate * 0.9 // Balanced speed
                utterance.pitchMultiplier = 0.94
            case .premium:
                utterance.rate = speechRate * 0.92 // Balanced speed
                utterance.pitchMultiplier = 0.95
            default:
                utterance.rate = speechRate * 0.95 // Balanced speed
                utterance.pitchMultiplier = 0.96
            }
        }
        
        currentUtterance = utterance
        
        speechSynthesizer.speak(utterance)
    }
    
    func pauseSpeech() {
        guard isSpeaking && !isPaused else { return }
        speechSynthesizer.pauseSpeaking(at: .immediate)
        isPaused = true
    }
    
    func resumeSpeech() {
        guard isPaused else { return }
        speechSynthesizer.continueSpeaking()
        isPaused = false
    }
    
    func stopSpeech() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        currentUtterance = nil
        isSpeaking = false
        isPaused = false
    }
    
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
        
        // ADVANCED: Enhanced natural speech formatting based on TTS research
        cleanText = cleanText.replacingOccurrences(of: "\n\n", with: "... ") // Double newlines become natural pauses
        cleanText = cleanText.replacingOccurrences(of: "\n", with: ", ") // Single newlines become comma pauses
        cleanText = cleanText.replacingOccurrences(of: "  ", with: " ") // Clean up extra spaces
        
        // Add natural speech transitions with longer pauses for better flow
        cleanText = cleanText.replacingOccurrences(of: ". However,", with: ".... However,")
        cleanText = cleanText.replacingOccurrences(of: ". Additionally,", with: ".... Additionally,")
        cleanText = cleanText.replacingOccurrences(of: ". Furthermore,", with: ".... Furthermore,")
        cleanText = cleanText.replacingOccurrences(of: ". For example,", with: ".... For example,")
        cleanText = cleanText.replacingOccurrences(of: ". Therefore,", with: ".... Therefore,")
        cleanText = cleanText.replacingOccurrences(of: ". In conclusion,", with: ".... In conclusion,")
        cleanText = cleanText.replacingOccurrences(of: ". On the other hand,", with: ".... On the other hand,")
        
        // Add breathing pauses after long sentences (sentences with 15+ words)
        let sentences = cleanText.components(separatedBy: ". ")
        cleanText = sentences.map { sentence in
            let wordCount = sentence.components(separatedBy: " ").count
            if wordCount > 15 && !sentence.hasSuffix("...") {
                return sentence + "..."
            }
            return sentence
        }.joined(separator: ". ")
        
        // Add slight pauses around numbers and percentages for clarity
        cleanText = cleanText.replacingOccurrences(of: " (", with: "... (")
        cleanText = cleanText.replacingOccurrences(of: ") ", with: ")... ")
        
        // Improve list reading with pauses
        cleanText = cleanText.replacingOccurrences(of: ", and ", with: ",... and ")
        
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleanText
    }
    
    // Helper function to get readable quality names
    private func getQualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .default:
            return "Default (Basic)"
        case .enhanced:
            return "Enhanced (High Quality)"
        case .premium:
            return "Premium (Siri-like/Personal)"
        @unknown default:
            return "Unknown (\(quality.rawValue))"
        }
    }
    
    // MARK: - Real-Time Chunk-Based TTS
    private func processChunkBasedTTS(partialResponse: String) {
        // Only process if we have meaningful new content
        guard partialResponse.count > lastSpokenLength else { return }
        
        // Extract new content since last speech
        let newContent = String(partialResponse.suffix(partialResponse.count - lastSpokenLength))
        
        // Check if we have enough content for a meaningful chunk (LONGER chunks for consistency)
        // OR if we hit a sentence boundary (. ! ?)
        let hasEnoughContent = newContent.count >= 80 // Increased from 50 to 80 for longer, more consistent chunks
        let hasSentenceBoundary = newContent.contains(". ") || newContent.contains("! ") || newContent.contains("? ")
        let hasNaturalPause = newContent.contains(", ") && newContent.count >= 60 // Increased from 30 to 60
        
        if hasEnoughContent || hasSentenceBoundary || hasNaturalPause {
            // Find the best chunk boundary (prefer sentence endings)
            let chunkToSpeak: String
            
            if let lastSentenceEnd = newContent.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
                // Speak up to the last complete sentence
                let endIndex = newContent.index(after: lastSentenceEnd)
                chunkToSpeak = String(newContent[..<endIndex])
            } else if let lastCommaIndex = newContent.lastIndex(of: ","), newContent.count >= 30 {
                // Speak up to the last comma for natural pause
                let endIndex = newContent.index(after: lastCommaIndex)
                chunkToSpeak = String(newContent[..<endIndex])
            } else if hasEnoughContent {
                // Speak the chunk as-is if we have enough content
                chunkToSpeak = newContent
            } else {
                return // Wait for more content
            }
            
            // Speak the chunk without stopping current speech (queue it)
            speakChunk(text: chunkToSpeak)
            
            // Update tracking
            lastSpokenLength += chunkToSpeak.count
            #if DEBUG
            print("🎙️ Real-time TTS chunk (\(chunkToSpeak.count) chars)")
            #endif
        }
    }
    
    private func speakChunk(text: String) {
        // Clean and speak a chunk without interrupting current speech
        let cleanText = cleanTextForSpeech(text)
        guard !cleanText.isEmpty else { return }
        
        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.voice = availableVoices.isEmpty ? nil : availableVoices[selectedVoiceIndex]
        
        // BALANCED SPEED: Slightly faster for better flow
        utterance.rate = speechRate * 0.95 // Faster than before but still consistent
        utterance.pitchMultiplier = 0.96 // Slightly higher pitch for clarity
        utterance.volume = 0.9
        
        // Shorter delays for better flow
        utterance.preUtteranceDelay = 0.15 // Shorter pause before speaking
        utterance.postUtteranceDelay = 0.2 // Shorter pause after speaking
        
        // Voice-specific optimizations - BALANCED speeds
        if let voice = utterance.voice {
            switch voice.quality {
            case .enhanced:
                utterance.rate = speechRate * 0.9 // Faster than before
                utterance.pitchMultiplier = 0.94
            case .premium:
                utterance.rate = speechRate * 0.92 // Faster than before
                utterance.pitchMultiplier = 0.95
            default:
                utterance.rate = speechRate * 0.95 // Faster than before
                utterance.pitchMultiplier = 0.96
            }
        }
        
        // Queue the chunk (don't stop current speech)
        speechSynthesizer.speak(utterance)
    }
    
    // MARK: - Manual TTS Controls
    
    func speakCurrentResponse() {
        // Manually speak the current/latest response when user presses speech button
        let textToSpeak = streamingResponse.isEmpty ? currentResponse : streamingResponse
        guard !textToSpeak.isEmpty else { return }
        
        speak(text: textToSpeak)
    }
    
    // MARK: - Voice & Speed Controls
    
    func setVoice(at index: Int) {
        guard index >= 0 && index < availableVoices.count else { return }
        selectedVoiceIndex = index
        selectedVoice = availableVoices[index]
    }
    
    func setSpeechRate(_ rate: Float) {
        speechRate = max(0.1, min(1.0, rate))
    }
    
    func testVoice() {
        let testText = "Hello, I'm Corra, your clinical trials assistant. This is how I sound with the current voice and speed settings."
        speak(text: testText)
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension ModelManager: AVSpeechSynthesizerDelegate {
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
