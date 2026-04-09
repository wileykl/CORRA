//
//  ChatView.swift
//  Main chat interface with safety boundaries
//

import SwiftUI

struct ChatView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var memoryManager: MemoryManager
    @EnvironmentObject var safetyBoundaries: SafetyBoundaries
    
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isGenerating = false
    @State private var showingSafetyAlert = false
    @State private var safetyAlertMessage = ""
    @State private var keyboardHeight: CGFloat = 0
    @State private var streamingMessageIndex: Int? = nil // Track which message is being streamed
    @FocusState private var isInputFocused: Bool // Track focus state for reliable text clearing
    
    init() {
        // Add welcome message matching web app
        _messages = State(initialValue: [
            ChatMessage(
                text: "Hi! I'm Corra, an AI assistant to help address questions about clinical trials. You can ask me about:\n\n✅ Clinical trial phases and procedures\n✅ Eligibility criteria and requirements\n✅ Understanding consent forms and protocols\n✅ General medical information related to trials\n\n💡 All processing happens on your device for complete privacy.",
                isUser: false,
                hasSafetyNotice: false
            )
        ])
    }
    
    private func clearConversation() {
        // Reset to just the welcome message
        messages = [
            ChatMessage(
                text: "Hi! I'm Corra, an AI assistant to help address questions about clinical trials. You can ask me about:\n\n✅ Clinical trial phases and procedures\n✅ Eligibility criteria and requirements\n✅ Understanding consent forms and protocols\n✅ General medical information related to trials\n\n💡 All processing happens on your device for complete privacy.",
                isUser: false,
                hasSafetyNotice: false
            )
        ]
        
        // Stop any ongoing speech
        modelManager.stopSpeech()
        
        // Reset streaming state
        streamingMessageIndex = nil
        isGenerating = false
        
        // Clear input text
        inputText = ""
        #if DEBUG
        print("🗑️ Conversation cleared")
        #endif
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages.indices, id: \.self) { index in
                            let message = messages[index]
                            
                            // Show streaming response for the latest AI message
                            if !message.isUser && index == streamingMessageIndex && isGenerating {
                                MessageBubble(message: ChatMessage(
                                    text: modelManager.streamingResponse.isEmpty ? "..." : modelManager.streamingResponse,
                                    isUser: false,
                                    hasSafetyNotice: message.hasSafetyNotice
                                ))
                                .id(message.id)
                            } else {
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        
                        if isGenerating && streamingMessageIndex == nil {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
                .background(Color(red: 42/255, green: 42/255, blue: 42/255)) // #2a2a2a
                .onChange(of: messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: modelManager.streamingResponse) { _ in
                    // Auto-scroll during streaming responses for real-time following
                    if isGenerating, let streamingIndex = streamingMessageIndex, streamingIndex < messages.count {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(messages[streamingIndex].id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Safety notice for off-topic
            if !inputText.isEmpty && !safetyBoundaries.isClinicallTrialRelated(inputText) {
                SafetyNoticeBar()
            }
            
            // Input area
            VStack(spacing: 0) {
                Divider()
                    .background(Color(red: 74/255, green: 74/255, blue: 74/255)) // #4a4a4a border
                
                HStack(spacing: 12) {
                    // Text field
                    TextField("Ask about clinical trials...", text: $inputText, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(10)
                        .background(Color(red: 31/255, green: 31/255, blue: 31/255)) // #1f1f1f input bg
                        .foregroundColor(Color.white)
                        .cornerRadius(20)
                        .lineLimit(1...4)
                        .focused($isInputFocused)
                        .onChange(of: inputText) { newValue in
                            // Limit input length
                            if newValue.count > 2000 {
                                inputText = String(newValue.prefix(2000))
                            }
                        }
                        .onSubmit {
                            if canSendMessage {
                                sendMessage()
                            }
                        }
                    
                    // Send button
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(canSendMessage ? Color(red: 74/255, green: 144/255, blue: 226/255) : Color(red: 74/255, green: 74/255, blue: 74/255)) // #4a90e2 : #4a4a4a
                    }
                    .disabled(!canSendMessage)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(Color(red: 42/255, green: 42/255, blue: 42/255)) // #2a2a2a
        }
        .alert("Safety Notice", isPresented: $showingSafetyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(safetyAlertMessage)
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = keyboardFrame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ClearConversation"))) { _ in
            clearConversation()
        }
    }
    
    private var canSendMessage: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isGenerating &&
        modelManager.isModelLoaded &&
        memoryManager.memoryPressure != .critical
    }
    
    private func sendMessage() {
        // Capture the input text FIRST before any state changes
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Guard against empty input
        guard !trimmedInput.isEmpty else { return }
        
        // Validate input through safety boundaries
        let validation = safetyBoundaries.validateInput(trimmedInput)
        
        if !validation.isValid {
            safetyAlertMessage = validation.message
            showingSafetyAlert = true
            return
        }
        
        // Check memory before generating
        if memoryManager.memoryPressure == .critical {
            safetyAlertMessage = "Memory is critically low. Please close other apps and try again."
            showingSafetyAlert = true
            return
        }
        
        // IMPORTANT: Clear input IMMEDIATELY and capture the prompt
        // This ensures the text field is cleared before any async operations
        let prompt = trimmedInput
        
        // Clear the text field - do this in a withAnimation block to ensure SwiftUI processes the change
        withAnimation {
            inputText = ""
        }
        
        // Dismiss keyboard focus to ensure TextField state is fully reset
        isInputFocused = false
        
        // Set generating state
        isGenerating = true
        
        // Add user message
        let userMessage = ChatMessage(
            text: prompt,
            isUser: true,
            hasSafetyNotice: false
        )
        messages.append(userMessage)
        
        // Add placeholder AI message for streaming
        let placeholderMessage = ChatMessage(
            text: "",
            isUser: false,
            hasSafetyNotice: false
        )
        messages.append(placeholderMessage)
        streamingMessageIndex = messages.count - 1
        
        // Generate STREAMING response
        modelManager.generateStreamingResponse(for: prompt) { [self] finalResponse in
            DispatchQueue.main.async {
                // Apply safety filtering
                let filteredResponse = safetyBoundaries.filterResponse(finalResponse, for: prompt)
                
                // Update the placeholder message with final response
                if let index = streamingMessageIndex, index < messages.count {
                    messages[index] = ChatMessage(
                        text: filteredResponse,
                        isUser: false,
                        hasSafetyNotice: filteredResponse.contains("⚠️")
                    )
                }
                
                // Reset streaming state
                streamingMessageIndex = nil
                isGenerating = false
                
                // Re-focus the input field after response is complete
                isInputFocused = true
            }
        }
    }
}

struct SafetyNoticeBar: View {
    var body: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundColor(.blue)
            
            Text("I specialize in clinical trial questions")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
    }
}

struct TypingIndicator: View {
    @State private var animationAmount = 1.0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationAmount)
                    .opacity(animationAmount == 1.0 ? 0.3 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: animationAmount
                    )
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
        .onAppear {
            animationAmount = 1.2
        }
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let hasSafetyNotice: Bool
    let timestamp = Date()
}
