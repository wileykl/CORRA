//
//  CorraCAGApp.swift
//  CorraCAG
//
//  Main app entry point with CAG framework integration
//

import SwiftUI

@main
struct CorraCAGApp: App {
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var memoryManager = MemoryManager.shared
    @StateObject private var safetyBoundaries = SafetyBoundaries.shared
    @StateObject private var cagManager = CAGManager.shared
    
    init() {
        // Configure app for medical use with CAG
        configureMedicalApp()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(modelManager)
                .environmentObject(memoryManager)
                .environmentObject(safetyBoundaries)
                .environmentObject(cagManager)
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
        // Set up medical app requirements
        print("[Corra] Corra Clinical Trials Assistant")
        print("[Corra] Version: 2.0.0")
        print("[Corra] Safety boundaries: ENABLED")
        print("[Corra] Memory management: ACTIVE")
        print("[Corra] CAG Framework: ENABLED")
    }
    
    private func initializeApp() {
        print("[Corra] Initializing Corra with CAG...")
        
        // Check CAG cache status
        if cagManager.isCacheLoaded {
            print("[Corra] CAG knowledge cache loaded")
        } else {
            print("[Corra] WARNING: CAG knowledge cache not loaded: \(cagManager.errorMessage)")
        }
        
        // Check device capabilities
        memoryManager.checkMemoryStatus()
        
        // Load model based on available memory
        if memoryManager.availableMemory > 4_000_000_000 {
            print("[Corra] Sufficient memory for full model")
            modelManager.loadModel()
        } else {
            print("[Corra] WARNING: Limited memory - using reduced configuration")
            modelManager.loadModelWithReducedConfig()
        }
        
        // Initialize safety system
        safetyBoundaries.initialize()
    }
    
    private func handleMemoryWarning() {
        print("[Corra] WARNING: Memory warning received")
        memoryManager.handleMemoryWarning()
        
        // Optionally reduce model memory footprint
        if memoryManager.memoryPressure == .critical {
            modelManager.reduceMemoryFootprint()
        }
    }
}
