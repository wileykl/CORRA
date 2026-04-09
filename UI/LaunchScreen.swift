//
//  LaunchScreen.swift
//  Custom launch screen matching Corra web app
//

import SwiftUI

struct LaunchScreen: View {
    @State private var ringScale: CGFloat = 0.8
    @State private var innerCircleScale: CGFloat = 0.5
    @State private var textOpacity: Double = 0
    
    private let coraBackground = Color(red: 42/255, green: 42/255, blue: 42/255) // #2a2a2a
    private let coraPrimary = Color(red: 74/255, green: 144/255, blue: 226/255) // #4a90e2
    
    var body: some View {
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
                        .opacity(textOpacity)
                    
                    // Blue circle with ring (matching web app)
                    ZStack {
                        // Outer ring
                        Circle()
                            .stroke(coraPrimary, lineWidth: 3)
                            .frame(width: 80, height: 80)
                            .scaleEffect(ringScale)
                        
                        // Inner filled circle
                        Circle()
                            .fill(coraBackground)
                            .frame(width: 74, height: 74)
                        
                        // Inner blue circle
                        Circle()
                            .fill(coraPrimary)
                            .frame(width: 40, height: 40)
                            .scaleEffect(innerCircleScale)
                    }
                }
                
                // Subtitle
                Text("AI assistant for clinical trials")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.white.opacity(0.8))
                    .opacity(textOpacity)
                
                // Loading indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: coraPrimary))
                    .scaleEffect(1.5)
                    .opacity(textOpacity)
            }
            .padding()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                ringScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                innerCircleScale = 1.0
            }
            withAnimation(.easeIn(duration: 0.8).delay(0.4)) {
                textOpacity = 1.0
            }
        }
    }
}

struct LaunchScreen_Previews: PreviewProvider {
    static var previews: some View {
        LaunchScreen()
    }
}

