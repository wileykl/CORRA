//
//  CorraApp.swift
//  Corra Clinical Trials Assistant
//
//  Main app entry point with safety and memory management
//

import SwiftUI

// NOTE: This file is kept for reference but not used as @main
// The main app entry point is CorraCAGApp.swift
struct CorraApp: App {
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var memoryManager = MemoryManager.shared
    @StateObject private var safetyBoundaries = SafetyBoundaries.shared
    
    init() {
        // Configure app for medical use
        configureMedicalApp()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(modelManager)
                .environmentObject(memoryManager)
                .environmentObject(safetyBoundaries)
                .onAppear {
                    initializeApp()
                }
                #if os(iOS)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    handleMemoryWarning()
                }
                #endif
        }
    }
    
    private func configureMedicalApp() {
        #if DEBUG
        print("Corra Clinical Trials Assistant")
        print("Version: 1.0.0 (Enhanced Simple)")
        print("Safety boundaries: ENABLED")
        print("Memory management: ACTIVE")
        #endif
    }
    
    private func initializeApp() {
        #if DEBUG
        print("Initializing Corra...")
        #endif
        
        // Check device capabilities
        memoryManager.checkMemoryStatus()
        
        // Load model based on available memory
        if memoryManager.availableMemory > 4_000_000_000 {
            modelManager.loadModel()
        } else {
            modelManager.loadModelWithReducedConfig()
        }
        
        // Initialize safety system
        safetyBoundaries.initialize()
    }
    
    private func handleMemoryWarning() {
        #if DEBUG
        print("Memory warning received")
        #endif
        memoryManager.handleMemoryWarning()
        
        // Optionally reduce model memory footprint
        if memoryManager.memoryPressure == .critical {
            modelManager.reduceMemoryFootprint()
        }
    }
}
