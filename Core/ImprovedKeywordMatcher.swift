//
//  ImprovedKeywordMatcher.swift
//  CorraCAG
//
//  Advanced keyword matching with stemming, synonyms, BM25, phrases, and fuzzy matching
//

import Foundation

// MARK: - Query Intent Types
enum QueryIntent {
    case protocolSpecific      // Questions about a specific trial/protocol (PI, sponsor, etc.)
    case generalClinicalTrial  // General questions about clinical trials
    case networkInformation    // Questions about Trial Innovation Network
    case eligibility           // Eligibility/criteria questions
    case safety                // Safety/side effects questions
    case process               // Process/procedure questions
    case unknown
}

class ImprovedKeywordMatcher {
    
    // MARK: - Protocol-Specific Indicators
    // These keywords strongly indicate the user is asking about a SPECIFIC trial/protocol
    private let protocolIndicators: Set<String> = [
        "pi", "principal investigator", "investigator", "sponsor", "listed",
        "protocol", "nct", "study number", "trial number", "irb",
        "site", "location", "enrollment", "enrolled", "recruiting",
        "start date", "end date", "phase", "arm", "cohort",
        "inclusion", "exclusion", "criteria", "eligible", "eligibility",
        "dose", "dosage", "schedule", "visit", "endpoint"
    ]
    
    // MARK: - Network/General Indicators
    // These keywords indicate questions about Trial Innovation Network or general info
    private let networkIndicators: Set<String> = [
        "innovation network", "trial innovation", "tin", "ctsa",
        "consortium", "hub", "recruitment support", "network",
        "collaborate", "partnership", "resource", "infrastructure"
    ]
    
    // MARK: - Medical Synonym Dictionary
    private let medicalSynonyms: [String: Set<String>] = [
        "cancer": ["oncology", "malignancy", "tumor", "carcinoma", "neoplasm", "cancerous"],
        "trial": ["study", "research", "clinical study", "investigation", "clinical research"],
        "eligibility": ["qualify", "eligible", "qualification", "criteria", "requirements"],
        "patient": ["participant", "subject", "volunteer", "individual"],
        "drug": ["medication", "therapy", "treatment", "pharmaceutical", "medicine"],
        "fda": ["food and drug administration", "regulatory", "approval", "federal drug administration"],
        "clinical": ["medical", "therapeutic", "treatment"],
        "disease": ["condition", "disorder", "illness", "syndrome"],
        "symptom": ["sign", "indication", "manifestation"],
        "diagnosis": ["diagnostic", "identification", "assessment"],
        "treatment": ["therapy", "intervention", "care", "management"],
        "medication": ["drug", "medicine", "pharmaceutical", "prescription"],
        "side effect": ["adverse effect", "reaction", "adverse event"],
        "dosage": ["dose", "amount", "quantity"],
        "protocol": ["procedure", "method", "guideline", "process"],
        "inclusion": ["include", "eligible", "qualify"],
        "exclusion": ["exclude", "ineligible", "disqualify"],
        "randomized": ["random", "randomization", "randomly assigned"],
        "placebo": ["control", "sham treatment"],
        "efficacy": ["effectiveness", "effect", "benefit"],
        "safety": ["safe", "tolerability", "adverse events"],
        "outcome": ["result", "endpoint", "measure"],
        "enrollment": ["recruitment", "enroll", "participant recruitment"],
        "consent": ["informed consent", "agreement", "permission"],
        "irb": ["institutional review board", "ethics committee", "review board"],
        "pi": ["principal investigator", "lead investigator", "study director"],
        "sponsor": ["funder", "funding organization", "pharmaceutical company"]
    ]
    
    // MARK: - Stop Words
    private let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by",
        "is", "are", "was", "were", "be", "been", "being", "have", "has", "had", "do", "does", "did",
        "will", "would", "could", "should", "may", "might", "can", "must", "shall",
        "this", "that", "these", "those", "i", "you", "he", "she", "it", "we", "they",
        "me", "him", "her", "us", "them", "my", "your", "his", "her", "its", "our", "their",
        "what", "when", "where", "why", "how", "who", "which", "whom", "whose"
    ]
    
    // MARK: - Keyword Extraction and Processing
    func extractAndProcessKeywords(from text: String) -> [String] {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && $0.count > 2 }
            .filter { !stopWords.contains($0) }
        
        // Stem words
        let stemmed = words.map { stemWord($0) }
        
        // Remove duplicates while preserving order
        var seen = Set<String>()
        var unique: [String] = []
        for word in stemmed {
            if !seen.contains(word) {
                seen.insert(word)
                unique.append(word)
            }
        }
        
        return unique
    }
    
    // MARK: - Word Stemming (Lightweight)
    func stemWord(_ word: String) -> String {
        var stemmed = word.lowercased()
        
        // Simple suffix removal (lightweight, no Porter stemmer needed)
        let suffixes = ["ing", "ed", "er", "est", "ly", "tion", "sion", "s", "es", "ies", "ied"]
        for suffix in suffixes.sorted(by: { $0.count > $1.count }) {  // Try longer suffixes first
            if stemmed.hasSuffix(suffix) && stemmed.count > suffix.count + 2 {
                stemmed = String(stemmed.dropLast(suffix.count))
                break
            }
        }
        
        return stemmed
    }
    
    // MARK: - Synonym Expansion
    func expandWithSynonyms(_ term: String) -> Set<String> {
        var expanded: Set<String> = [term, stemWord(term)]
        
        // Direct synonym lookup
        if let synonyms = medicalSynonyms[term] {
            expanded.formUnion(synonyms)
        }
        
        // Check if stemmed version has synonyms
        let stemmed = stemWord(term)
        if let synonyms = medicalSynonyms[stemmed] {
            expanded.formUnion(synonyms)
        }
        
        // Check all synonyms for their synonyms (one level deep)
        for synonym in expanded {
            if let nestedSynonyms = medicalSynonyms[synonym] {
                expanded.formUnion(nestedSynonyms)
            }
        }
        
        return expanded
    }
    
    // MARK: - Phrase Extraction
    func extractPhrases(from query: String) -> [String] {
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        var phrases: [String] = []
        
        // Extract 2-word and 3-word phrases
        for i in 0..<words.count {
            if i + 1 < words.count {
                let phrase = "\(words[i]) \(words[i+1])"
                if phrase.count > 5 && !stopWords.contains(words[i]) {
                    phrases.append(phrase)
                }
            }
            if i + 2 < words.count {
                let phrase = "\(words[i]) \(words[i+1]) \(words[i+2])"
                if phrase.count > 8 && !stopWords.contains(words[i]) {
                    phrases.append(phrase)
                }
            }
        }
        
        return phrases
    }
    
    // MARK: - Query Intent Detection
    func detectQueryIntent(from query: String) -> QueryIntent {
        let queryLower = query.lowercased()
        
        // Check for protocol-specific indicators FIRST (higher priority)
        var protocolScore = 0
        var networkScore = 0
        
        for indicator in protocolIndicators {
            if queryLower.contains(indicator) {
                protocolScore += 2
                #if DEBUG
                print("[KeywordMatcher] Found protocol indicator: '\(indicator)'")
                #endif
            }
        }
        
        for indicator in networkIndicators {
            if queryLower.contains(indicator) {
                networkScore += 2
                #if DEBUG
                print("[KeywordMatcher] Found network indicator: '\(indicator)'")
                #endif
            }
        }
        
        // Check for specific patterns that indicate protocol questions
        let protocolPatterns = [
            "the trial", "this trial", "the study", "this study",
            "on the protocol", "in the protocol", "the protocol",
            "who is the", "what is the", "where is the",
            "listed on", "listed in", "according to"
        ]
        for pattern in protocolPatterns {
            if queryLower.contains(pattern) {
                protocolScore += 1
            }
        }
        
        // Check for network-specific patterns
        let networkPatterns = [
            "innovation network", "trial innovation", "what is tin",
            "about the network", "network services"
        ]
        for pattern in networkPatterns {
            if queryLower.contains(pattern) {
                networkScore += 3  // Strong indicator
            }
        }
        
        #if DEBUG
        print("[KeywordMatcher] Intent scores - Protocol: \(protocolScore), Network: \(networkScore)")
        #endif
        
        // Determine intent based on scores
        if networkScore > 0 && networkScore > protocolScore {
            return .networkInformation
        } else if protocolScore > 0 {
            return .protocolSpecific
        }
        
        // Check for other intents
        if queryLower.contains("eligib") || queryLower.contains("criteria") || queryLower.contains("qualify") {
            return .eligibility
        }
        if queryLower.contains("safe") || queryLower.contains("side effect") || queryLower.contains("adverse") {
            return .safety
        }
        if queryLower.contains("how do") || queryLower.contains("process") || queryLower.contains("procedure") {
            return .process
        }
        
        return .generalClinicalTrial
    }
    
    // MARK: - High-Value Keywords for Protocol Questions
    func getHighValueKeywords(for intent: QueryIntent) -> Set<String> {
        switch intent {
        case .protocolSpecific:
            return [
                "principal", "investigator", "pi", "sponsor", "protocol",
                "nct", "phase", "arm", "cohort", "site", "location",
                "enrollment", "inclusion", "exclusion", "criteria",
                "dose", "dosage", "schedule", "endpoint", "irb"
            ]
        case .networkInformation:
            return [
                "innovation", "network", "tin", "ctsa", "consortium",
                "hub", "recruitment", "support", "resource", "infrastructure"
            ]
        case .eligibility:
            return [
                "eligibility", "eligible", "criteria", "inclusion", "exclusion",
                "qualify", "requirements", "age", "condition", "diagnosis"
            ]
        case .safety:
            return [
                "safety", "safe", "adverse", "side", "effect", "risk",
                "toxicity", "monitoring", "event"
            ]
        default:
            return []
        }
    }
    
    // MARK: - Term Frequency Computation
    func computeTermFrequencies(_ text: String, keywords: [String]) -> [String: Int] {
        let textLower = text.lowercased()
        var frequencies: [String: Int] = [:]
        
        for keyword in keywords {
            // Count exact matches
            let count = textLower.components(separatedBy: keyword).count - 1
            if count > 0 {
                frequencies[keyword] = count
            }
            
            // Also count stemmed versions
            let stemmed = stemWord(keyword)
            if stemmed != keyword {
                let stemmedCount = textLower.components(separatedBy: stemmed).count - 1
                if stemmedCount > 0 {
                    frequencies[stemmed] = (frequencies[stemmed] ?? 0) + stemmedCount
                }
            }
        }
        
        return frequencies
    }
    
    // MARK: - BM25 Scoring
    func calculateBM25Score(
        chunk: KnowledgeChunk,
        queryTerms: [String],
        avgChunkLength: Double,
        totalChunks: Int,
        keywordIndex: [String: [KeywordIndexEntry]]
    ) -> Double {
        let k1 = 1.5  // BM25 parameter
        let b = 0.75  // BM25 parameter
        
        var score = 0.0
        
        for term in queryTerms {
            // Get term frequency from chunk
            let termFreq = Double(chunk.keywords[term] ?? 0)
            
            // Calculate IDF (Inverse Document Frequency)
            let chunksWithTerm = Double(keywordIndex[term]?.count ?? 1)
            let idf = log((Double(totalChunks) + 1) / (chunksWithTerm + 1))
            
            // BM25 formula
            let numerator = termFreq * (k1 + 1)
            let denominator = termFreq + k1 * (1 - b + b * (Double(chunk.length) / avgChunkLength))
            score += idf * (numerator / denominator)
        }
        
        return score
    }
    
    // MARK: - Fuzzy Matching (Levenshtein Distance)
    func fuzzyMatch(_ word: String, against target: String, maxDistance: Int = 2) -> Bool {
        let distance = levenshteinDistance(word, target)
        return distance <= maxDistance && distance < word.count / 2  // Only if reasonable
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        
        var matrix = Array(repeating: Array(repeating: 0, count: s2Array.count + 1), count: s1Array.count + 1)
        
        // Initialize first row and column
        for i in 0...s1Array.count {
            matrix[i][0] = i
        }
        for j in 0...s2Array.count {
            matrix[0][j] = j
        }
        
        // Fill matrix
        for i in 1...s1Array.count {
            for j in 1...s2Array.count {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // Deletion
                    matrix[i][j-1] + 1,      // Insertion
                    matrix[i-1][j-1] + cost  // Substitution
                )
            }
        }
        
        return matrix[s1Array.count][s2Array.count]
    }
    
    // MARK: - Find Relevant Chunks (Main Method)
    func findRelevantChunks(
        query: String,
        keywordIndex: [String: [KeywordIndexEntry]],
        chunkIndex: [KnowledgeChunk],
        maxResults: Int
    ) -> [Int] {
        guard !chunkIndex.isEmpty else { return [] }
        
        // Step 0: Detect query intent
        let intent = detectQueryIntent(from: query)
        let highValueKeywords = getHighValueKeywords(for: intent)
        #if DEBUG
        print("[KeywordMatcher] Detected intent: \(intent)")
        #endif
        
        // Step 1: Extract and expand keywords
        let baseKeywords = extractAndProcessKeywords(from: query)
        var expandedTerms: Set<String> = []
        for keyword in baseKeywords {
            expandedTerms.formUnion(expandWithSynonyms(keyword))
        }
        let queryTerms = Array(expandedTerms)
        
        // Step 2: Extract phrases
        let phrases = extractPhrases(from: query)
        
        // Step 3: Find candidate chunks
        var candidateChunks: Set<Int> = []
        
        // Find chunks matching query terms
        for term in queryTerms {
            if let entries = keywordIndex[term] {
                for entry in entries {
                    candidateChunks.insert(entry.chunkId)
                }
            }
        }
        
        // Find chunks matching phrases
        for phrase in phrases {
            let phraseTerms = phrase.components(separatedBy: " ")
            if phraseTerms.count >= 2 {
                // Find chunks containing all words in phrase
                var phraseChunks: Set<Int>?
                for term in phraseTerms {
                    if let entries = keywordIndex[term] {
                        let chunkIds = Set(entries.map { $0.chunkId })
                        if phraseChunks == nil {
                            phraseChunks = chunkIds
                        } else {
                            phraseChunks = phraseChunks?.intersection(chunkIds)
                        }
                    }
                }
                if let phraseChunks = phraseChunks {
                    candidateChunks.formUnion(phraseChunks)
                }
            }
        }
        
        // Step 4: Calculate BM25 scores with intent-based adjustments
        let avgChunkLength = Double(chunkIndex.map { $0.length }.reduce(0, +)) / Double(chunkIndex.count)
        let totalChunks = chunkIndex.count
        
        var scoredChunks: [(Int, Double)] = []
        for chunkId in candidateChunks {
            guard chunkId < chunkIndex.count else { continue }
            let chunk = chunkIndex[chunkId]
            
            var score = calculateBM25Score(
                chunk: chunk,
                queryTerms: queryTerms,
                avgChunkLength: avgChunkLength,
                totalChunks: totalChunks,
                keywordIndex: keywordIndex
            )
            
            // INTENT-BASED SCORING ADJUSTMENTS
            
            // Boost chunks that contain high-value keywords for the detected intent
            var highValueMatchCount = 0
            for keyword in highValueKeywords {
                if chunk.keywords[keyword] != nil || chunk.keywords[stemWord(keyword)] != nil {
                    highValueMatchCount += 1
                }
            }
            if highValueMatchCount > 0 {
                let boost = 1.0 + (Double(highValueMatchCount) * 0.3)  // 30% boost per high-value match
                score *= boost
                #if DEBUG
                print("[KeywordMatcher] Chunk \(chunkId) boosted by \(boost)x for \(highValueMatchCount) high-value matches")
                #endif
            }
            
            // PENALTY: If intent is protocol-specific, penalize chunks with "innovation network" content
            // but WITHOUT protocol-specific keywords
            if intent == .protocolSpecific {
                let hasNetworkTerms = chunk.keywords["innovation"] != nil || chunk.keywords["network"] != nil
                let hasProtocolTerms = chunk.keywords["investigator"] != nil ||
                                       chunk.keywords["pi"] != nil ||
                                       chunk.keywords["principal"] != nil ||
                                       chunk.keywords["sponsor"] != nil ||
                                       chunk.keywords["protocol"] != nil ||
                                       chunk.keywords["nct"] != nil
                
                if hasNetworkTerms && !hasProtocolTerms {
                    score *= 0.3  // 70% penalty for network-only chunks when asking protocol questions
                    #if DEBUG
                    print("[KeywordMatcher] Chunk \(chunkId) penalized (network content for protocol question)")
                    #endif
                }
            }
            
            // PENALTY: If intent is network-specific, penalize protocol-only chunks
            if intent == .networkInformation {
                let hasNetworkTerms = chunk.keywords["innovation"] != nil || chunk.keywords["network"] != nil
                if !hasNetworkTerms {
                    score *= 0.5  // 50% penalty for non-network chunks
                }
            }
            
            scoredChunks.append((chunkId, score))
        }
        
        // Step 5: Sort by score and return top N
        scoredChunks.sort { $0.1 > $1.1 }
        
        #if DEBUG
        print("[KeywordMatcher] Top \(min(5, scoredChunks.count)) chunks by score")
        #endif
        
        let topChunks = scoredChunks.prefix(maxResults).map { $0.0 }
        
        return Array(topChunks)
    }
}

