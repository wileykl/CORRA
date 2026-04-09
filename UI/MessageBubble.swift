//
//  MessageBubble.swift
//  Chat message bubble component
//

import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    @EnvironmentObject var modelManager: ModelManager
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // Message content
                Text(message.text)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(message.isUser ? .trailing : .leading)
                    .padding(12)
                    .background(backgroundColor)
                    .foregroundColor(textColor)
                    .cornerRadius(16)
                    .contextMenu {
                        Button(action: {
                            #if os(iOS)
                            UIPasteboard.general.string = message.text
                            #else
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                            #endif
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        
                        // Speech button for AI messages only
                        if !message.isUser {
                            Button(action: {
                                modelManager.speak(text: message.text)
                            }) {
                                Label("Speak", systemImage: "speaker.wave.2")
                            }
                        }
                    }
                
                // Safety notice if present
                if message.hasSafetyNotice && !message.isUser {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                        Text("Medical Information Notice")
                            .font(.caption2)
                    }
                    .foregroundColor(.orange)
                }
                
                // Timestamp
                Text(timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: getMaxWidth(), alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser {
                Spacer()
            }
        }
    }
    
    private var backgroundColor: Color {
        if message.isUser {
            return Color(red: 74/255, green: 144/255, blue: 226/255) // #4a90e2
        } else {
            return Color(red: 58/255, green: 58/255, blue: 58/255) // #3a3a3a
        }
    }
    
    private var textColor: Color {
        if message.isUser {
            return .white
        } else {
            return Color.white
        }
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
    
    private func getMaxWidth() -> CGFloat {
        #if os(iOS)
        return UIScreen.main.bounds.width * 0.75
        #else
        return 400 // Fixed width for macOS
        #endif
    }
}
