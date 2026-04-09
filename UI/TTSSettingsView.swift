//
//  TTSSettingsView.swift
//  CorraApp - Siri Voice & Speed Control Settings
//

import SwiftUI
import AVFoundation

struct TTSSettingsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @Environment(\.dismiss) private var dismiss
    
    private let coraPrimary = Color(red: 74/255, green: 144/255, blue: 226/255) // #4a90e2
    private let coraBackground = Color(red: 42/255, green: 42/255, blue: 42/255) // #2a2a2a
    private let coraMessageBg = Color(red: 58/255, green: 58/255, blue: 58/255) // #3a3a3a
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                headerView
                ScrollView {
                    VStack(spacing: 24) {
                        speechRateControl
                        voiceSelectionView
                        Spacer()
                    }
                    .padding(.horizontal)
                }
            }
            .background(coraBackground)
            .navigationTitle("Voice Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    dismiss()
                }
                .foregroundColor(coraPrimary)
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.dark)
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 40))
                .foregroundColor(coraPrimary)
            
            Text("Corra Voice Settings")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("Customize how Corra speaks to you")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.top, 20)
    }
    
    private var speechRateControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "speedometer")
                    .foregroundColor(coraPrimary)
                Text("Speech Speed")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(modelManager.speechRate * 100))%")
                    .font(.caption)
                    .foregroundColor(coraPrimary)
            }
            
            HStack {
                Image(systemName: "tortoise.fill")
                    .foregroundColor(.gray)
                    .font(.caption)
                
                Slider(value: $modelManager.speechRate, in: 0.1...1.0, step: 0.05) {
                    Text("Speed")
                } minimumValueLabel: {
                    Text("Slow")
                        .font(.caption2)
                        .foregroundColor(.gray)
                } maximumValueLabel: {
                    Text("Fast")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .accentColor(coraPrimary)
                
                Image(systemName: "hare.fill")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            
            Button(action: {
                modelManager.testVoice()
            }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Test Speed")
                }
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(coraPrimary)
                .cornerRadius(8)
            }
        }
        .padding(16)
        .background(coraMessageBg)
        .cornerRadius(12)
    }
    
    private var voiceSelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.wave.2.fill")
                    .foregroundColor(coraPrimary)
                Text("Siri Voice")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("\(modelManager.availableVoices.count) voices")
                    .font(.caption)
                    .foregroundColor(coraPrimary)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(0..<modelManager.availableVoices.count, id: \.self) { index in
                    let voice = modelManager.availableVoices[index]
                    let isSelected = index == modelManager.selectedVoiceIndex
                    
                    Button(action: {
                        modelManager.setVoice(at: index)
                        // Test the new voice immediately
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            modelManager.testVoice()
                        }
                    }) {
                        VStack(spacing: 6) {
                            HStack {
                                let iconName: String = {
                                    if voice.name.lowercased().contains("samantha") {
                                        return "star.fill"
                                    } else if voice.gender == .female {
                                        return "person.crop.circle.fill"
                                    } else {
                                        return "person.crop.circle"
                                    }
                                }()
                                Image(systemName: iconName)
                                    .foregroundColor(isSelected ? .white : coraPrimary)
                                    .font(.title3)
                                
                                Spacer()
                                
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(voice.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(isSelected ? .white : .white.opacity(0.9))
                                    .lineLimit(1)
                                
                                HStack {
                                    Text(voice.language)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    
                                    Spacer()
                                    
                                    // Voice quality indicator
                                    HStack(spacing: 2) {
                                        ForEach(0..<Int(voice.quality.rawValue), id: \.self) { _ in
                                            Circle()
                                                .fill(coraPrimary)
                                                .frame(width: 4, height: 4)
                                        }
                                        ForEach(Int(voice.quality.rawValue)..<3, id: \.self) { _ in
                                            Circle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(width: 4, height: 4)
                                        }
                                    }
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(12)
                        .background(isSelected ? coraPrimary : coraBackground.opacity(0.8))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? .white : coraPrimary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(16)
        .background(coraMessageBg)
        .cornerRadius(12)
    }
}

// MARK: - Preview
struct TTSSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        TTSSettingsView()
            .environmentObject(ModelManager.shared)
    }
}
