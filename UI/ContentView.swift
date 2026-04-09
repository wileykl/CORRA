//
//  ContentView.swift
//  CorraCAG
//
//  Main content view that hosts the chat interface with CAG integration
//

import SwiftUI
import AVFAudio

struct ContentView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var memoryManager: MemoryManager
    @EnvironmentObject var safetyBoundaries: SafetyBoundaries
    @EnvironmentObject var cagManager: CAGManager
    
    @State private var showingLaunchScreen = true
    @State private var launchRingScale: CGFloat = 0.8
    @State private var launchInnerCircleScale: CGFloat = 0.5
    @State private var launchTextOpacity: Double = 0
    
    private let coraBackground = Color(red: 42/255, green: 42/255, blue: 42/255) // #2a2a2a
    private let coraPrimary = Color(red: 74/255, green: 144/255, blue: 226/255) // #4a90e2
    
    var body: some View {
        ZStack {
            NavigationView {
                VStack(spacing: 0) {
                    // Memory status bar
                    MemoryStatusBar()
                    
                    // Main chat interface
                    ChatView()
                    
                    // Model loading overlay
                    if !modelManager.isModelLoaded {
                        ModelLoadingOverlay()
                    }
                }
                .navigationTitle("Corra")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(
                    trailing: HStack {
                        // Clear Conversation Button
                        Button(action: {
                            // Send clear conversation notification
                            NotificationCenter.default.post(name: NSNotification.Name("ClearConversation"), object: nil)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .accessibilityLabel("Clear conversation")
                        
                        // Voice Selection Menu
                        Menu {
                            Section("Voice") {
                                ForEach(0..<modelManager.availableVoices.count, id: \.self) { index in
                                    Button(action: {
                                        modelManager.setVoice(at: index)
                                        modelManager.testVoice()
                                    }) {
                                        HStack {
                                            Text(modelManager.availableVoices[index].name)
                                            if index == modelManager.selectedVoiceIndex {
                                                Spacer()
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Section("Speed") {
                                Button("Slow (30%)") {
                                    modelManager.setSpeechRate(0.3)
                                    modelManager.testVoice()
                                }
                                Button("Medium (50%)") {
                                    modelManager.setSpeechRate(0.5)
                                    modelManager.testVoice()
                                }
                                Button("Fast (70%)") {
                                    modelManager.setSpeechRate(0.7)
                                    modelManager.testVoice()
                                }
                                Button("Very Fast (90%)") {
                                    modelManager.setSpeechRate(0.9)
                                    modelManager.testVoice()
                                }
                            }
                        } label: {
                            Image(systemName: "gear")
                                .foregroundColor(coraPrimary)
                        }
                        .accessibilityLabel("Voice and speed settings")
                        
                        // Current voice indicator
                        if !modelManager.availableVoices.isEmpty {
                            Text(modelManager.availableVoices[modelManager.selectedVoiceIndex].name.prefix(8))
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        // Manual Speech Button
                        Button(action: {
                            modelManager.speakCurrentResponse()
                        }) {
                            Image(systemName: modelManager.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                                .foregroundColor(modelManager.isSpeaking ? coraPrimary : .blue)
                        }
                        .accessibilityLabel("Speak current response")
                        
                        // TTS Control Buttons (when speaking)
                        if modelManager.isSpeaking {
                            Button(action: {
                                if modelManager.isPaused {
                                    modelManager.resumeSpeech()
                                } else {
                                    modelManager.pauseSpeech()
                                }
                            }) {
                                Image(systemName: modelManager.isPaused ? "play.fill" : "pause.fill")
                                    .foregroundColor(coraPrimary)
                            }
                            .accessibilityLabel(modelManager.isPaused ? "Resume speech" : "Pause speech")
                            
                            Button(action: {
                                modelManager.stopSpeech()
                            }) {
                                Image(systemName: "stop.fill")
                                    .foregroundColor(.red)
                            }
                            .accessibilityLabel("Stop speech")
                        }
                        
                        // CAG Status Indicator
                        if cagManager.isCacheLoaded {
                            Image(systemName: "book.fill")
                                .foregroundColor(.green)
                                .accessibilityLabel("CAG cache loaded")
                        }
                    }
                )
                .background(coraBackground)
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .preferredColorScheme(.dark)  // Force dark mode to match web app
            
            // Launch screen overlay
            if showingLaunchScreen {
                ZStack {
                    // Background
                    coraBackground
                        .ignoresSafeArea()
                    
                    VStack(spacing: 40) {
                        // Header with title and blue circle
                        HStack(spacing: 20) {
                            Text("Hi I'm Corra")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(.white)
                                .opacity(launchTextOpacity)
                            
                            // Blue circle with ring (matching web app)
                            ZStack {
                                // Outer ring
                                Circle()
                                    .stroke(coraPrimary, lineWidth: 3)
                                    .frame(width: 80, height: 80)
                                    .scaleEffect(launchRingScale)
                                
                                // Inner filled circle
                                Circle()
                                    .fill(coraBackground)
                                    .frame(width: 74, height: 74)
                                
                                // Inner blue circle
                                Circle()
                                    .fill(coraPrimary)
                                    .frame(width: 40, height: 40)
                                    .scaleEffect(launchInnerCircleScale)
                            }
                        }
                        
                        // Subtitle
                        Text("AI assistant for clinical trials")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(.white.opacity(0.8))
                            .opacity(launchTextOpacity)
                        
                        // CAG Status
                        if cagManager.isCacheLoaded {
                            Text("CAG Framework Active")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.green.opacity(0.8))
                                .opacity(launchTextOpacity)
                        }
                        
                        // Loading indicator
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: coraPrimary))
                            .scaleEffect(1.5)
                            .opacity(launchTextOpacity)
                    }
                    .padding()
                }
                .transition(.opacity)
                .zIndex(1)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.6)) {
                        launchRingScale = 1.0
                    }
                    withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                        launchInnerCircleScale = 1.0
                    }
                    withAnimation(.easeIn(duration: 0.8).delay(0.4)) {
                        launchTextOpacity = 1.0
                    }
                }
            }
        }
        .onAppear {
            #if DEBUG
            if cagManager.isCacheLoaded {
                print("[CAG] CAG cache loaded - \(cagManager.documentSources.count) documents available")
            } else {
                print("[CAG] WARNING: CAG cache not loaded")
            }
            #endif
            
            // Hide launch screen after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showingLaunchScreen = false
                }
            }
        }
    }
}

struct ModelLoadingOverlay: View {
    @EnvironmentObject var modelManager: ModelManager
    
    private let coraPrimary = Color(red: 74/255, green: 144/255, blue: 226/255) // #4a90e2
    private let coraBackground = Color(red: 42/255, green: 42/255, blue: 42/255) // #2a2a2a
    private let coraMessageBg = Color(red: 58/255, green: 58/255, blue: 58/255) // #3a3a3a
    private let coraError = Color(red: 255/255, green: 59/255, blue: 48/255) // Red for errors
    
    var body: some View {
        ZStack {
            coraBackground.opacity(0.95)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                if !modelManager.errorMessage.isEmpty {
                    // Error state
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(coraError)
                    
                    Text("Model Loading Failed")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(modelManager.errorMessage)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Text("Please check Xcode console for details")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.top, 8)
                } else {
                    // Loading state
                    ZStack {
                        Circle()
                            .stroke(coraPrimary, lineWidth: 3)
                            .frame(width: 80, height: 80)
                        
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: coraPrimary))
                    }
                    
                    Text("Loading Clinical Trials AI Model...")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("\(Int(modelManager.loadingProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(coraPrimary)
                    
                    Text("Model: LLaMA 3.2 3B (CAG)")
                        .font(.caption2)
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }
            .padding(30)
            .background(coraMessageBg)
            .cornerRadius(20)
        }
    }
}

struct MemoryStatusBar: View {
    @EnvironmentObject var memoryManager: MemoryManager
    
    private let coraPrimary = Color(red: 74/255, green: 144/255, blue: 226/255) // #4a90e2
    private let coraMessageBg = Color(red: 58/255, green: 58/255, blue: 58/255) // #3a3a3a
    
    var body: some View {
        HStack {
            Image(systemName: memoryManager.memoryPressure.icon)
                .foregroundColor(memoryManager.memoryPressure == .normal ? coraPrimary : memoryManager.memoryPressure.color)
            
            Text(memoryManager.memoryPressure.statusText)
                .font(.caption)
                .foregroundColor(Color.white.opacity(0.7))
            
            Spacer()
            
            if memoryManager.memoryPressure != .normal {
                Button(action: {
                    // Show memory tips
                }) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(coraPrimary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(coraMessageBg.opacity(0.5))
        .animation(.easeInOut, value: memoryManager.memoryPressure)
    }
}

// Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ModelManager.shared)
            .environmentObject(MemoryManager.shared)
            .environmentObject(SafetyBoundaries.shared)
            .environmentObject(CAGManager.shared)
    }
}
