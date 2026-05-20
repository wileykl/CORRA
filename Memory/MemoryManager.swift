//
//  MemoryManager.swift
//  Memory management and monitoring system
//

import Foundation
import Combine
import SwiftUI
#if os(iOS)
import UIKit
#endif
import os

class MemoryManager: ObservableObject {
    static let shared = MemoryManager()
    
    @Published var memoryPressure: MemoryPressure = .normal
    @Published var availableMemory: Int64 = 0
    @Published var usedMemory: Int64 = 0
    
    private var memoryTimer: Timer?
    private var memoryWarningObserver: NSObjectProtocol?
    
    enum MemoryPressure {
        case normal
        case warning  
        case critical
        
        var contextSize: Int32 {
            switch self {
            case .normal: return 4096
            case .warning: return 2048
            case .critical: return 1024
            }
        }
        
        var maxTokens: Int {
            switch self {
            case .normal: return 300
            case .warning: return 150
            case .critical: return 75
            }
        }
        
        var gpuLayers: Int32 {
            switch self {
            case .normal: return -1  // Use all
            case .warning: return 20
            case .critical: return 10
            }
        }
        
        var icon: String {
            switch self {
            case .normal: return "checkmark.circle"
            case .warning: return "exclamationmark.triangle"
            case .critical: return "exclamationmark.octagon"
            }
        }
        
        var color: Color {
            switch self {
            case .normal: return .green
            case .warning: return .orange
            case .critical: return .red
            }
        }
        
        var statusText: String {
            switch self {
            case .normal: return "Memory: Normal"
            case .warning: return "Memory: Limited (Reduced performance)"
            case .critical: return "Memory: Critical (Minimal mode)"
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .normal: return Color.clear
            case .warning: return Color.orange.opacity(0.1)
            case .critical: return Color.red.opacity(0.1)
            }
        }
    }
    
    private init() {
        setupMemoryMonitoring()
    }
    
    private func setupMemoryMonitoring() {
        // Register for memory warnings
        #if os(iOS)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
        #endif
        
        // Start periodic memory monitoring
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkMemoryStatus()
        }
        
        // Initial check
        checkMemoryStatus()
    }
    
    func checkMemoryStatus() {
        // Get total physical memory
        let memInfo = ProcessInfo.processInfo
        let totalMemory = memInfo.physicalMemory
        
        // Get current memory usage
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            usedMemory = Int64(info.resident_size)
            availableMemory = Int64(totalMemory) - usedMemory
            
            // Update pressure level based on device
            updateMemoryPressure(totalMemory: Int64(totalMemory))
            
            #if DEBUG
            let usedMB = usedMemory / 1024 / 1024
            let availableMB = availableMemory / 1024 / 1024
            print("💾 Memory: Used \(usedMB)MB, Available \(availableMB)MB, Pressure: \(memoryPressure)")
            #endif
        }
    }
    
    private func updateMemoryPressure(totalMemory: Int64) {
        // Determine device type and adjust thresholds
        #if os(iOS)
        let deviceModel = UIDevice.current.userInterfaceIdiom
        let isPhone = deviceModel == .phone
        #else
        let isPhone = false
        #endif
        
        if isPhone {
            // iPhone thresholds
            if totalMemory < 6_000_000_000 { // Less than 6GB (iPhone 14 Pro)
                // More aggressive memory management
                if availableMemory < 500_000_000 { // Less than 500MB
                    memoryPressure = .critical
                } else if availableMemory < 1_000_000_000 { // Less than 1GB
                    memoryPressure = .warning
                } else {
                    memoryPressure = .normal
                }
            } else { // 6GB+ (iPhone 14 Pro/15 Pro)
                if availableMemory < 1_000_000_000 { // Less than 1GB
                    memoryPressure = .critical
                } else if availableMemory < 2_000_000_000 { // Less than 2GB
                    memoryPressure = .warning
                } else {
                    memoryPressure = .normal
                }
            }
        } else { // iPad or Mac
            if availableMemory < 1_500_000_000 { // Less than 1.5GB
                memoryPressure = .critical
            } else if availableMemory < 3_000_000_000 { // Less than 3GB
                memoryPressure = .warning
            } else {
                memoryPressure = .normal
            }
        }
    }
    
    func handleMemoryWarning() {
        os_log(.error, "Memory warning received")
        memoryPressure = .critical
        
        // Clear any caches
        ResponseCache.shared.clear()
        
        // Force garbage collection if possible
        URLCache.shared.removeAllCachedResponses()
        
        // Notify model manager to reduce resources
        NotificationCenter.default.post(
            name: Notification.Name("ReduceModelResources"),
            object: nil
        )
    }
    
    func canLoadFullModel() -> Bool {
        // Check if we have enough memory for the 3B model
        // Model needs ~3-4GB, so we want at least 4GB available
        return availableMemory > 4_000_000_000
    }
    
    func getRecommendedConfiguration() -> ModelConfiguration {
        return ModelConfiguration(
            contextSize: memoryPressure.contextSize,
            gpuLayers: memoryPressure.gpuLayers,
            maxTokens: memoryPressure.maxTokens,
            useMlock: memoryPressure != .critical,
            useMmap: true
        )
    }
    
    deinit {
        memoryTimer?.invalidate()
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// Response cache for memory efficiency
class ResponseCache {
    static let shared = ResponseCache()
    private var cache: [String: String] = [:]
    private let maxCacheSize = 20
    private let queue = DispatchQueue(label: "com.corra.responsecache")
    
    private init() {}
    
    func store(prompt: String, response: String) {
        guard MemoryManager.shared.memoryPressure == .normal else { return }
        
        queue.async {
            self.cache[prompt] = response
            
            // Limit cache size
            if self.cache.count > self.maxCacheSize {
                if let firstKey = self.cache.keys.first {
                    self.cache.removeValue(forKey: firstKey)
                }
            }
        }
    }
    
    func retrieve(for prompt: String) -> String? {
        queue.sync {
            return cache[prompt]
        }
    }
    
    func clear() {
        queue.async {
            self.cache.removeAll()
        }
    }
}

// Model configuration based on memory
struct ModelConfiguration {
    let contextSize: Int32
    let gpuLayers: Int32
    let maxTokens: Int
    let useMlock: Bool
    let useMmap: Bool
}
