//
//  ColorScheme.swift
//  Corra color scheme matching the web app
//

import SwiftUI

extension Color {
    // Corra Web App Colors
    static let coraBackground = Color(hex: "2a2a2a")      // Dark gray background
    static let coraText = Color(hex: "ffffff")             // White text
    static let coraPrimary = Color(hex: "4a90e2")          // Primary blue
    static let coraSecondary = Color(hex: "357abd")        // Darker blue for gradients
    static let coraMessageBg = Color(hex: "3a3a3a")        // Slightly lighter for messages
    static let coraInputBg = Color(hex: "1f1f1f")          // Darker for input fields
    static let coraBorder = Color(hex: "4a4a4a")           // Border color
    
    // Gradient matching web app
    static let coraGradient = LinearGradient(
        gradient: Gradient(colors: [Color.coraPrimary, Color.coraSecondary]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Initialize from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

