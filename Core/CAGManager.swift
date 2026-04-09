//
//  CAGManager.swift
//  CorraCAG
//
//  Manages Cache Augmented Generation (CAG) knowledge cache
//  Uses lazy loading + in-memory indexing for efficient memory usage
//

import Foundation
import Combine

// MARK: - Chunk Index Structure
struct KnowledgeChunk {
    let id: Int
    let position: Range<Int>  // Position in the original knowledge text
    let keywords: [String: Int]  // Pre-computed term frequencies
    let length: Int
    // Note: text is NOT stored here - loaded on-demand from file
}

// MARK: - Keyword Index Entry
struct KeywordIndexEntry {
    let chunkId: Int
    let termFrequency: Int
    let position: Range<Int>
}

// MARK: - CAG Manager with Lazy Loading
class CAGManager: ObservableObject {
    static let shared = CAGManager()
    
    @Published var isCacheLoaded = false
    @Published var errorMessage = ""
    
    private(set) var knowledgePrompt: String = ""
    private var knowledgeTextFileURL: URL?  // Reference to JSON file
    private var knowledgeTextCacheFileURL: URL?  // Cached knowledge text file
    private var knowledgeTextRaw: String?  // Only loaded temporarily during indexing
    private var knowledgeTextFileCache: String?  // File-level cache (loaded on-demand, cleared when needed)
    private(set) var documentSources: [String] = []
    
    // Lazy loading components
    private var chunkIndex: [KnowledgeChunk] = []
    private var keywordIndex: [String: [KeywordIndexEntry]] = [:]  // term -> [chunk entries]
    private var chunkCache: [Int: String] = [:]  // LRU cache for frequently used chunks
    private let maxCacheSize = 50  // Maximum cached chunks
    private var cacheAccessOrder: [Int] = []  // For LRU eviction
    
    // Keyword matching components
    private let keywordMatcher = ImprovedKeywordMatcher()
    
    // Indexing state
    private var isIndexed = false
    private let chunkSize = 1000  // Characters per chunk
    private let chunkOverlap = 200  // Overlap between chunks
    
    private init() {
        loadKnowledgeCache()
    }
    
    // MARK: - Knowledge Cache Loading (Lazy)
    func loadKnowledgeCache() {
        #if DEBUG
        print("[CAG] Loading CAG knowledge cache...")
        #endif
        
        guard let cacheURL = Bundle.main.url(forResource: "knowledge_cache", withExtension: "json") else {
            errorMessage = "Knowledge cache file not found in bundle"
            return
        }
        
        do {
            let cacheData = try Data(contentsOf: cacheURL)
            guard let cache = try JSONSerialization.jsonObject(with: cacheData) as? [String: Any] else {
                errorMessage = "Failed to parse knowledge cache"
                return
            }
            
            // Extract knowledge prompt (always loaded - small)
            if let prompt = cache["knowledge_prompt"] as? String {
                knowledgePrompt = prompt
                #if DEBUG
                print("[CAG] Loaded knowledge prompt (\(prompt.count) characters)")
                #endif
            }
            
            // Store knowledge text file reference (lazy loading)
            // We'll build index from the raw data, but don't keep it in memory
            if let text = cache["knowledge_text"] as? String {
                // Store temporarily to build index, then clear
                knowledgeTextRaw = text
                knowledgeTextFileURL = cacheURL  // Reference for potential file-based access
                #if DEBUG
                print("[CAG] Knowledge text available (\(text.count) characters) - will build index")
                #endif
            }
            
            // Extract document sources
            if let sources = cache["document_sources"] as? [String] {
                documentSources = sources
                #if DEBUG
                print("[CAG] Loaded \(sources.count) document sources")
                #endif
            }
            
            // Build index in background (non-blocking)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.buildIndex()
            }
            
            isCacheLoaded = true
            #if DEBUG
            print("[CAG] CAG knowledge cache loaded successfully (index building in background)")
            #endif
            
        } catch {
            errorMessage = "Failed to load knowledge cache: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Index Building
    private func buildIndex() {
        guard let text = knowledgeTextRaw, !text.isEmpty else {
            return
        }
        
        #if DEBUG
        print("[CAG] Building keyword index...")
        #endif
        let startTime = Date()
        
        // Chunk the knowledge text
        var chunks: [KnowledgeChunk] = []
        var currentPos = 0
        var chunkId = 0
        
        while currentPos < text.count {
            let endPos = min(currentPos + chunkSize, text.count)
            let chunkText = String(text[text.index(text.startIndex, offsetBy: currentPos)..<text.index(text.startIndex, offsetBy: endPos)])
            
            // Extract keywords and compute term frequencies
            let keywords = keywordMatcher.extractAndProcessKeywords(from: chunkText)
            let termFreq = keywordMatcher.computeTermFrequencies(chunkText, keywords: keywords)
            
            let chunk = KnowledgeChunk(
                id: chunkId,
                position: currentPos..<endPos,
                keywords: termFreq,
                length: chunkText.count
            )
            chunks.append(chunk)
            
            // Build keyword index
            for (term, freq) in termFreq {
                if keywordIndex[term] == nil {
                    keywordIndex[term] = []
                }
                keywordIndex[term]?.append(KeywordIndexEntry(
                    chunkId: chunkId,
                    termFrequency: freq,
                    position: currentPos..<endPos
                ))
            }
            
            // Move to next chunk with overlap
            currentPos = max(currentPos + 1, endPos - chunkOverlap)
            chunkId += 1
        }
        
        chunkIndex = chunks
        
        // Save knowledge text to a cache file for on-demand loading
        if let text = knowledgeTextRaw, let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let cacheFile = cacheDir.appendingPathComponent("knowledge_text_cache.txt")
            do {
                try text.write(to: cacheFile, atomically: true, encoding: .utf8)
                knowledgeTextCacheFileURL = cacheFile
            } catch {
                // Keep in memory as fallback
            }
        }
        
        // Clear raw text from memory (index is built, text is in cache file)
        knowledgeTextRaw = nil
        
        #if DEBUG
        let buildTime = Date().timeIntervalSince(startTime)
        print("[CAG] Index built: \(chunks.count) chunks, \(keywordIndex.count) unique terms in \(String(format: "%.2f", buildTime))s")
        print("[CAG] Memory saved: Knowledge text cleared, only index in memory (~\(estimateIndexSize())MB)")
        #endif
        
        isIndexed = true
    }
    
    private func estimateIndexSize() -> Int {
        // Rough estimate: chunks + keyword index
        let chunkSize = chunkIndex.count * 500  // ~500 bytes per chunk entry
        let keywordSize = keywordIndex.count * 100  // ~100 bytes per keyword entry
        return (chunkSize + keywordSize) / (1024 * 1024)  // Convert to MB
    }
    
    // MARK: - Lazy Chunk Retrieval
    private func getChunk(id: Int) -> String? {
        // Check cache first
        if let cached = chunkCache[id] {
            // Update LRU order
            cacheAccessOrder.removeAll { $0 == id }
            cacheAccessOrder.append(id)
            return cached
        }
        
        // Load from file using position range
        guard id < chunkIndex.count else { return nil }
        let chunk = chunkIndex[id]
        
        // Load chunk text from cache file
        guard let cacheFileURL = knowledgeTextCacheFileURL else {
            // Fallback: try to load from original JSON
            return loadChunkFromJSON(id: id, position: chunk.position)
        }
        
        guard let chunkText = loadChunkFromFile(url: cacheFileURL, position: chunk.position) else {
            return nil
        }
        
        // Cache it
        cacheChunk(id: id, text: chunkText)
        
        return chunkText
    }
    
    // Load chunk text from cache file using position range
    private func loadChunkFromFile(url: URL, position: Range<Int>) -> String? {
        // Load file into cache if not already loaded
        if knowledgeTextFileCache == nil {
            guard let fileContent = try? String(contentsOf: url, encoding: .utf8) else {
                return nil
            }
            knowledgeTextFileCache = fileContent
        }
        
        guard let fileContent = knowledgeTextFileCache else {
            return nil
        }
        
        // Extract chunk using character positions
        let startIndex = fileContent.index(fileContent.startIndex, offsetBy: position.lowerBound)
        let endIndex = fileContent.index(fileContent.startIndex, offsetBy: position.upperBound)
        return String(fileContent[startIndex..<endIndex])
    }
    
    // Fallback: load chunk from original JSON if cache file unavailable
    private func loadChunkFromJSON(id: Int, position: Range<Int>) -> String? {
        guard let jsonURL = knowledgeTextFileURL else { return nil }
        
        do {
            let cacheData = try Data(contentsOf: jsonURL)
            guard let cache = try JSONSerialization.jsonObject(with: cacheData) as? [String: Any],
                  let text = cache["knowledge_text"] as? String else {
                return nil
            }
            
            let startIndex = text.index(text.startIndex, offsetBy: position.lowerBound)
            let endIndex = text.index(text.startIndex, offsetBy: position.upperBound)
            return String(text[startIndex..<endIndex])
        } catch {
            #if DEBUG
            print("[CAG] ERROR: Failed to load chunk from JSON: \(error)")
            #endif
            return nil
        }
    }
    
    private func cacheChunk(id: Int, text: String) {
        // Implement LRU eviction
        if chunkCache.count >= maxCacheSize && !chunkCache.keys.contains(id) {
            // Evict least recently used
            if let lruId = cacheAccessOrder.first {
                chunkCache.removeValue(forKey: lruId)
                cacheAccessOrder.removeFirst()
            }
        }
        
        chunkCache[id] = text
        cacheAccessOrder.append(id)
    }
    
    // MARK: - Relevant Knowledge Retrieval
    func getRelevantKnowledge(for query: String, maxChunks: Int = 5) -> String {
        // Wait for index if not ready
        if !isIndexed {
            return ""  // Don't return full text - too large!
        }
        
        let startTime = Date()
        
        // Find relevant chunks using improved keyword matching
        let relevantChunkIds = keywordMatcher.findRelevantChunks(
            query: query,
            keywordIndex: keywordIndex,
            chunkIndex: chunkIndex,
            maxResults: maxChunks
        )
        
        // Retrieve chunk texts
        var relevantChunks: [String] = []
        for chunkId in relevantChunkIds {
            if let chunkText = getChunk(id: chunkId) {
                relevantChunks.append(chunkText)
            }
        }
        
        #if DEBUG
        let retrievalTime = Date().timeIntervalSince(startTime)
        print("[CAG] Retrieved \(relevantChunks.count) relevant chunks in \(String(format: "%.2f", retrievalTime * 1000))ms")
        #endif
        
        // If no chunks found, return empty (don't fallback to full text)
        if relevantChunks.isEmpty {
            return ""
        }
        
        return relevantChunks.joined(separator: "\n\n")
    }
    
    // MARK: - CAG Prompt Building
    func buildCAGPrompt(userQuestion: String) -> String {
        // Get relevant knowledge chunks (lazy loaded) - even if cache not loaded, try to get knowledge
        let relevantKnowledge = isCacheLoaded ? getRelevantKnowledge(for: userQuestion) : ""
        
        // Detect user's language
        let userLanguage = detectLanguage(userQuestion)
        
        // Build system prompt with CAG knowledge
        // CRITICAL: Language instruction at the very top
        var systemContent = "CRITICAL LANGUAGE RULE: You MUST respond ONLY in \(userLanguage). If the user asks in English, you MUST respond ONLY in English. If the user asks in Spanish, you MUST respond ONLY in Spanish. NEVER mix multiple languages in a single response. Even if the knowledge provided contains multiple languages, your response must be ONLY in \(userLanguage).\n\n"
        
        systemContent += "You are Corra, a friendly and knowledgeable AI assistant who specializes in clinical trials.\n\n"
        systemContent += "Your personality:\n"
        systemContent += "- Warm, approachable, and patient\n"
        systemContent += "- Expert in clinical trials but explains things simply\n"
        systemContent += "- Always helpful and encouraging\n\n"
        systemContent += "Your rules:\n"
        systemContent += "1. ONLY answer questions related to clinical trials, medical research, drug development, patient participation, FDA processes, or related medical topics\n"
        systemContent += "2. Explain everything in simple, clear language that anyone can understand\n"
        systemContent += "3. Use everyday examples and analogies when helpful\n"
        systemContent += "4. Be accurate but avoid overwhelming medical jargon\n"
        systemContent += "5. If asked about non-clinical trial topics, politely redirect to clinical trials\n"
        systemContent += "6. When creating lists (questions, steps, etc.), ensure each item is unique and avoid repetition\n"
        systemContent += "7. LANGUAGE ENFORCEMENT: You MUST respond ONLY in \(userLanguage). Do NOT include any text in other languages. If you see multilingual content in the knowledge provided, translate it to \(userLanguage) or ignore it. Your entire response must be in \(userLanguage) only.\n\n"
        systemContent += "For non-clinical trial questions, respond with:\n"
        systemContent += "\"I'm sorry but I can only answer questions related to clinical trials. I can provide clinical trial information in multiple languages including Spanish, French, German, Italian, and Portuguese.\"\n\n"
        systemContent += "Important: Never mention that you're explaining things at any particular age or education level. Just keep your language naturally clear and simple."
        
        // Add CAG knowledge to system prompt if available
        if !relevantKnowledge.isEmpty {
            let maxKnowledgeLength = 6000  // ~8000 tokens max
            let truncatedKnowledge = String(relevantKnowledge.prefix(maxKnowledgeLength))
            systemContent += "\n\nRelevant Knowledge:\n\(truncatedKnowledge)"
        }
        
        // Build full LLaMA 3.2 chat template (matching working app)
        let fullPrompt = "<|start_header_id|>system<|end_header_id|>\n\n"
            + systemContent
            + "<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n"
            + userQuestion
            + "<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
        
        return fullPrompt
    }
    
    func getKnowledgeContext() -> String {
        // Return empty - use getRelevantKnowledge instead
        return ""
    }
    
    // MARK: - Language Detection
    private func detectLanguage(_ text: String) -> String {
        let lowercased = text.lowercased()
        
        // STEP 1: Check for UNIQUE language identifiers first (these are definitive)
        
        // Spanish: Inverted question/exclamation marks are UNIQUE to Spanish
        if lowercased.contains("¿") || lowercased.contains("¡") {
            return "Spanish"
        }
        
        // German: Unique characters ß, and umlauts in German context
        if lowercased.contains("ß") {
            return "German"
        }
        
        // STEP 2: Use a scoring system to count pattern matches for each language
        var scores: [String: Int] = [
            "Spanish": 0,
            "French": 0,
            "German": 0,
            "Italian": 0,
            "Portuguese": 0,
            "English": 0
        ]
        
        // Spanish patterns (weighted: unique words = 3, common = 1)
        let spanishUniquePatterns = [
            "qué", "quién", "cómo", "cuál", "cuáles", "dónde", "cuándo", "por qué",
            "español", "ensayo", "clínico", "clínica", "investigador",
            "está", "puedo", "necesito", "quiero", "años", "niño", "niña"
        ]
        let spanishCommonPatterns = [
            "el ", "la ", "los ", "las ", "del ", "al ",
            "es ", "son ", "puede"
        ]
        for pattern in spanishUniquePatterns {
            if lowercased.contains(pattern) { scores["Spanish"]! += 3 }
        }
        for pattern in spanishCommonPatterns {
            if lowercased.contains(pattern) { scores["Spanish"]! += 1 }
        }
        
        // French patterns (weighted)
        let frenchUniquePatterns = [
            "qu'est-ce", "pourquoi", "français", "médecin", "médicament",
            "étude", "recherche", "je ", "vous ", "nous ", "puis-je",
            "c'est", "n'est", "l'", "d'", "aujourd'hui", "être", "très"
        ]
        let frenchCommonPatterns = [
            "le ", "la ", "les ", "un ", "une ", "des ", "du ", "de la",
            "comment", "quand", "qui ", "quel", "quelle", "est ", "sont "
        ]
        for pattern in frenchUniquePatterns {
            if lowercased.contains(pattern) { scores["French"]! += 3 }
        }
        for pattern in frenchCommonPatterns {
            if lowercased.contains(pattern) { scores["French"]! += 1 }
        }
        
        // German patterns (weighted)
        let germanUniquePatterns = [
            "warum", "deutsch", "klinische", "studie", "arzt", "behandlung",
            "medikament", "forschung", "protokoll", "ich ", "möchte",
            "über", "für", "müssen", "können", "würde", "hätte"
        ]
        let germanCommonPatterns = [
            "was ist", "wie ", "wann", "wer ", "welche",
            "der ", "die ", "das ", "ein ", "eine ", "einem",
            "ist ", "sind ", "kann "
        ]
        for pattern in germanUniquePatterns {
            if lowercased.contains(pattern) { scores["German"]! += 3 }
        }
        for pattern in germanCommonPatterns {
            if lowercased.contains(pattern) { scores["German"]! += 1 }
        }
        
        // Italian patterns (weighted)
        let italianUniquePatterns = [
            "cos'è", "perché", "italiano", "paziente", "trattamento",
            "farmaco", "ricerca", "protocollo", "posso", "vorrei",
            "anche", "questa", "questo", "della", "degli", "delle"
        ]
        let italianCommonPatterns = [
            "come ", "quando", "chi ", "quale",
            "il ", "lo ", "i ", "gli ", "uno ",
            "è ", "sono "
        ]
        for pattern in italianUniquePatterns {
            if lowercased.contains(pattern) { scores["Italian"]! += 3 }
        }
        for pattern in italianCommonPatterns {
            if lowercased.contains(pattern) { scores["Italian"]! += 1 }
        }
        
        // Portuguese patterns (weighted)
        let portugueseUniquePatterns = [
            "o que é", "português", "pesquisa", "médico",
            "quero", "preciso", "também", "você", "isso",
            "ão", "ões", "ção", "ções", "não", "são"
        ]
        let portugueseCommonPatterns = [
            "como ", "por que", "quando", "quem ", "qual",
            "os ", "as ", "um ", "uma ", "do ", "da ",
            "é "
        ]
        for pattern in portugueseUniquePatterns {
            if lowercased.contains(pattern) { scores["Portuguese"]! += 3 }
        }
        for pattern in portugueseCommonPatterns {
            if lowercased.contains(pattern) { scores["Portuguese"]! += 1 }
        }
        
        // English patterns (weighted) - check for common English words
        let englishUniquePatterns = [
            "what", "who", "where", "when", "why", "how",
            "the ", "this ", "that ", "these ", "those ",
            "clinical", "trial", "study", "research", "patient",
            "drug", "treatment", "protocol", "investigator"
        ]
        let englishCommonPatterns = [
            " is ", " are ", " was ", " were ", " be ",
            " to ", " of ", " in ", " for ", " on ", " with ",
            " and ", " or ", " but ", " if ", " can ", " will "
        ]
        for pattern in englishUniquePatterns {
            if lowercased.contains(pattern) { scores["English"]! += 3 }
        }
        for pattern in englishCommonPatterns {
            if lowercased.contains(pattern) { scores["English"]! += 1 }
        }
        
        // Find the language with the highest score
        let sortedScores = scores.sorted { $0.value > $1.value }
        
        // If highest score is greater than 0, use that language
        if let topScore = sortedScores.first, topScore.value > 0 {
            return topScore.key
        }
        
        // Default to English if no patterns matched
        return "English"
    }
}

