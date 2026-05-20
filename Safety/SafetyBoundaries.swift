//
//  SafetyBoundaries.swift
//  Safety system ported from Python implementation
//

import Foundation
import Combine

class SafetyBoundaries: ObservableObject {
    static let shared = SafetyBoundaries()
    
    // Clinical trial keywords from Python cora.py
    private let clinicalKeywords = [
        "clinical trial", "clinical study", "medical research", "drug development",
        "placebo", "fda", "phase 1", "phase 2", "phase 3", "phase 4",
        "patient", "participant", "treatment", "medication", "therapy",
        "side effect", "efficacy", "safety", "protocol", "consent",
        "randomized", "double-blind", "control group", "experimental",
        "pharmaceutical", "medicine", "disease", "condition", "symptom",
        "doctor", "researcher", "hospital", "clinic", "health", "medical",
        "trial", "study", "research", "test", "testing", "experiment",
        "volunteer", "enroll", "recruitment", "criteria", "eligibility",
        "principal investigator", "pi", "investigator", "researcher", "protocol",
        // TIN/Network related
        "innovation network", "trial innovation", "tin", "ctsa", "consortium",
        "recruitment support", "network", "hub"
    ]
    
    // Dangerous patterns for adversarial defense
    private let dangerousPatterns = [
        "ignore previous", "disregard instructions", "forget what i said",
        "system prompt", "jailbreak", "bypass", "override",
        "<script>", "javascript:", "onclick", "onerror",
        "drop table", "select from", "insert into", "delete from"
    ]
    
    // Personal medical advice patterns to filter (refined to allow clinical trial anxiety discussions)
    private let personalAdvicePatterns = [
        // English patterns
        "you should take this medication", "you must take this drug", "stop taking your medication",
        "your specific diagnosis is", "your medical condition requires", "your treatment plan should be",
        "I prescribe", "prescription for you specifically", "you need this treatment",
        // Spanish patterns
        "debes tomar este medicamento", "tienes que tomar esta medicina", "deja de tomar tu medicamento",
        "tu diagnóstico específico es", "tu condición médica requiere", "te receto",
        // French patterns
        "vous devez prendre ce médicament", "vous devez arrêter de prendre", "votre diagnostic spécifique est",
        "votre condition médicale nécessite", "je vous prescris",
        // German patterns
        "sie sollten dieses medikament nehmen", "sie müssen dieses medikament nehmen", "ihre spezifische diagnose ist",
        "ich verschreibe ihnen",
        // Italian patterns
        "dovresti prendere questo farmaco", "devi prendere questo medicinale", "la tua diagnosi specifica è",
        "ti prescrivo",
        // Portuguese patterns
        "você deve tomar este medicamento", "você precisa tomar este remédio", "seu diagnóstico específico é",
        "eu prescrevo para você"
    ]
    
    private init() {}
    
    func initialize() {
        #if DEBUG
        print("Safety boundaries initialized")
        print("Clinical keywords loaded: \(clinicalKeywords.count)")
        print("Dangerous patterns loaded: \(dangerousPatterns.count)")
        #endif
    }
    
    // MARK: - Input Validation
    
    func isClinicallTrialRelated(_ input: String) -> Bool {
        let lowercased = input.lowercased()
        
        // Check English keywords
        let hasEnglishKeywords = clinicalKeywords.contains { keyword in
            lowercased.contains(keyword)
        }
        
        // Check for foreign language clinical trial terms
        let hasForeignLanguageKeywords = checkForeignLanguageClinicalTerms(lowercased)
        
        // Check for language request patterns (e.g., "in Spanish", "translate to", "respond in", "give in French")
        let isLanguageRequest = lowercased.contains("in spanish") || 
                               lowercased.contains("in french") || 
                               lowercased.contains("in german") || 
                               lowercased.contains("in italian") || 
                               lowercased.contains("in portuguese") || 
                               lowercased.contains("translate") || 
                               lowercased.contains("respond in") || 
                               lowercased.contains("answer in") ||
                               lowercased.contains("explain in") ||
                               // NEW: Catch "give/provide the answer in [language]" patterns
                               (lowercased.contains("give") && (lowercased.contains("french") || lowercased.contains("spanish") || lowercased.contains("german") || lowercased.contains("italian"))) ||
                               (lowercased.contains("provide") && (lowercased.contains("french") || lowercased.contains("spanish") || lowercased.contains("german") || lowercased.contains("italian"))) ||
                               // Catch standalone language names in context
                               lowercased.contains("french") || lowercased.contains("spanish") || lowercased.contains("german") || lowercased.contains("italian")
        
        // For language requests, also check if the question contains clinical trial content
        if isLanguageRequest {
            // Remove language request words to check the underlying content
            let contentWithoutLanguage = lowercased
                .replacingOccurrences(of: "in spanish", with: "")
                .replacingOccurrences(of: "in french", with: "")
                .replacingOccurrences(of: "in german", with: "")
                .replacingOccurrences(of: "in italian", with: "")
                .replacingOccurrences(of: "in portuguese", with: "")
                .replacingOccurrences(of: "translate", with: "")
                .replacingOccurrences(of: "respond in", with: "")
                .replacingOccurrences(of: "answer in", with: "")
                .replacingOccurrences(of: "explain in", with: "")
                .replacingOccurrences(of: "spanish", with: "")
                .replacingOccurrences(of: "french", with: "")
                .replacingOccurrences(of: "german", with: "")
                .replacingOccurrences(of: "italian", with: "")
                .replacingOccurrences(of: "portuguese", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check if the remaining content has clinical trial keywords
            let hasClinicalContent = clinicalKeywords.contains { keyword in
                contentWithoutLanguage.contains(keyword)
            } || checkForeignLanguageClinicalTerms(contentWithoutLanguage)
            
            // Only allow language requests if there's clinical trial content
            return hasClinicalContent
        }
        
        return hasEnglishKeywords || hasForeignLanguageKeywords
    }
    
    private func checkForeignLanguageClinicalTerms(_ input: String) -> Bool {
        // Common clinical trial terms in major languages
        let foreignClinicalTerms = [
            // Spanish
            "ensayo clínico", "estudio clínico", "investigación médica", "fase", "placebo", "tratamiento",
            "medicamento", "terapia", "paciente", "participante", "consentimiento", "fármaco",
            "red de innovación", "innovación de ensayos", // TIN-related
            // French  
            "essai clinique", "étude clinique", "recherche médicale", "phase", "traitement", "médicament",
            "thérapie", "patient", "participant", "consentement", "médicament",
            "réseau d'innovation", "innovation des essais", // TIN-related
            // German
            "klinische studie", "medizinische forschung", "phase", "behandlung", "medikament", 
            "therapie", "patient", "teilnehmer", "einverständnis", "arzneimittel",
            "innovationsnetzwerk", "trial innovation", "netzwerk für klinische", // TIN-related
            "forschungsnetzwerk", "studiennetzwerk", // Research network terms
            // Italian
            "studio clinico", "ricerca medica", "fase", "trattamento", "farmaco",
            "terapia", "paziente", "partecipante", "consenso", "medicina",
            "rete di innovazione", "innovazione degli studi", // TIN-related
            // Portuguese
            "estudo clínico", "pesquisa médica", "fase", "tratamento", "medicamento",
            "terapia", "paciente", "participante", "consentimento", "remédio",
            "rede de inovação", "inovação de ensaios" // TIN-related
        ]
        
        return foreignClinicalTerms.contains { term in
            input.contains(term)
        }
    }
    
    func validateInput(_ input: String) -> (isValid: Bool, message: String) {
        // Check length
        if input.count > 2000 {
            return (false, "Message is too long. Please keep it under 2000 characters.")
        }
        
        if input.count < 2 {
            return (false, "Message is too short.")
        }
        
        // Check for dangerous patterns
        let lowercased = input.lowercased()
        for pattern in dangerousPatterns {
            if lowercased.contains(pattern) {
                return (false, "Invalid input detected. Please rephrase your question.")
            }
        }
        
        // Always allow input - let the LLM handle clinical trial focus with polite redirects
        return (true, "")
    }
    
    // MARK: - Language Filtering
    
    private func filterLanguageMismatch(_ response: String, query: String) -> String {
        // Detect query language
        let queryLower = query.lowercased()
        let isQueryEnglish = !containsNonEnglishIndicators(queryLower)
        
        #if DEBUG
        print("[Safety] Query language detection - isEnglish: \(isQueryEnglish)")
        #endif
        
        // If query is English, filter out non-English content from response
        if isQueryEnglish {
            let filtered = removeNonEnglishContent(response)
            #if DEBUG
            if filtered != response {
                print("[Safety] Response was filtered (language mismatch detected in response)")
            }
            #endif
            return filtered
        }
        
        // For non-English queries, keep response as-is (model should handle it)
        #if DEBUG
        print("[Safety] Non-English query detected - preserving response language")
        #endif
        return response
    }
    
    private func containsNonEnglishIndicators(_ text: String) -> Bool {
        // UNIQUE CHARACTERS: Check for language-specific characters first (most reliable)
        // German unique characters
        if text.contains("ä") || text.contains("ö") || text.contains("ü") || text.contains("ß") {
            return true
        }
        // Spanish unique characters
        if text.contains("¿") || text.contains("¡") || text.contains("ñ") {
            return true
        }
        // French unique characters (some shared with Portuguese)
        if text.contains("ç") || text.contains("œ") || text.contains("æ") {
            return true
        }
        // Portuguese/Spanish accented vowels
        if text.contains("ã") || text.contains("õ") {
            return true
        }
        
        // Spanish indicators
        if text.contains("qué") || text.contains("cómo") || text.contains("cuál") ||
           text.contains("español") || text.contains("ensayo") || text.contains("clínico") ||
           text.contains("quién") || text.contains("dónde") || text.contains("cuándo") ||
           text.contains("por qué") || text.contains("investigador") || text.contains("protocolo") {
            return true
        }
        
        // French indicators
        if text.contains("qu'est-ce") || text.contains("comment") || text.contains("français") ||
           text.contains("essai") || text.contains("clinique") || text.contains("pourquoi") ||
           text.contains("est-ce que") || text.contains("qu'est") || text.contains("réseau") {
            return true
        }
        
        // German indicators - EXPANDED with common question words and TIN-related terms
        if text.contains("was ist") || text.contains("wie ") || text.contains("deutsch") ||
           text.contains("klinische") || text.contains("studie") ||
           text.contains("warum") || text.contains("wann") || text.contains("wer ") ||
           text.contains("welche") || text.contains("können") || text.contains("kannst") ||
           text.contains("netzwerk") || text.contains("innovation") || // TIN-related
           text.contains("erzähl") || text.contains("erkläre") || text.contains("beschreib") ||
           text.contains("über das") || text.contains("über die") || text.contains("über den") ||
           text.contains("mir ") || text.contains("bitte") ||
           text.contains("forschung") || text.contains("behandlung") || text.contains("patient") {
            return true
        }
        
        // Italian indicators
        if text.contains("cos'è") || text.contains("come ") || text.contains("italiano") ||
           text.contains("studio") || text.contains("clinico") || text.contains("perché") ||
           text.contains("qual è") || text.contains("chi è") || text.contains("rete") {
            return true
        }
        
        // Portuguese indicators
        if text.contains("o que é") || text.contains("como ") || text.contains("português") ||
           text.contains("estudo") || text.contains("clínico") || text.contains("por que") ||
           text.contains("quem é") || text.contains("qual é") || text.contains("rede") {
            return true
        }
        
        return false
    }
    
    private func removeNonEnglishContent(_ text: String) -> String {
        // Check if text contains list formatting (bullets, dashes, etc.)
        let hasListFormatting = text.contains("•") || text.contains("- ") || text.contains("* ") || 
                               text.contains("\n-") || text.contains("\n•") || text.contains("\n*")
        
        if hasListFormatting {
            // Preserve list structure by processing line-by-line
            let lines = text.components(separatedBy: "\n")
            var filteredLines: [String] = []
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                // Preserve empty lines (they're part of formatting)
                if trimmedLine.isEmpty {
                    filteredLines.append("")
                    continue
                }
                
                let lineLower = trimmedLine.lowercased()
                let hasNonEnglishLine = containsNonEnglishIndicators(lineLower)
                let nonASCIIRatioLine = Double(trimmedLine.unicodeScalars.filter { !$0.isASCII }.count) / Double(max(trimmedLine.count, 1))
                let likelyNonEnglishLine = nonASCIIRatioLine > 0.3 && trimmedLine.count > 10
                
                if !hasNonEnglishLine && !likelyNonEnglishLine {
                    filteredLines.append(line)
                }
            }
            
            let filtered = filteredLines.joined(separator: "\n")
            
            // If filtering removed too much, return original
            if filtered.count < text.count / 2 && text.count > 50 {
                return text
            }
            
            return filtered.isEmpty ? text : filtered
        } else {
            // For regular text, preserve paragraph structure
            let paragraphs = text.components(separatedBy: "\n\n")
            var englishParagraphs: [String] = []
            
            for paragraph in paragraphs {
                // Split paragraph into sentences for filtering
                let sentences = paragraph.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                var englishSentences: [String] = []
                
                for sentence in sentences {
                    let trimmed = sentence.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        continue
                    }
                    
                    // Check if sentence contains non-English indicators
                    let lowercased = trimmed.lowercased()
                    let hasNonEnglish = containsNonEnglishIndicators(lowercased)
                    
                    // Also check for high ratio of non-ASCII characters (likely non-English)
                    let nonASCIIRatio = Double(trimmed.unicodeScalars.filter { !$0.isASCII }.count) / Double(max(trimmed.count, 1))
                    let likelyNonEnglish = nonASCIIRatio > 0.3 && trimmed.count > 10
                    
                    if !hasNonEnglish && !likelyNonEnglish {
                        englishSentences.append(trimmed)
                    }
                }
                
                // Rejoin sentences within paragraph
                if !englishSentences.isEmpty {
                    englishParagraphs.append(englishSentences.joined(separator: ". "))
                }
            }
            
            // Rejoin paragraphs with double newlines to preserve structure
            let filtered = englishParagraphs.joined(separator: "\n\n")
            
            // If filtering removed too much, return original
            if filtered.count < text.count / 2 && text.count > 50 {
                return text
            }
            
            return filtered.isEmpty ? text : filtered
        }
    }
    
    // MARK: - Response Filtering
    
    func filterResponse(_ response: String, for query: String) -> String {
        var filtered = response
        
        #if DEBUG
        print("[Safety] filterResponse called - query length: \(query.count), response length: \(response.count)")
        #endif
        
        // LANGUAGE FILTERING: Remove non-matching language content
        filtered = filterLanguageMismatch(filtered, query: query)
        
        #if DEBUG
        if filtered.count < response.count * 3 / 4 {
            print("[Safety] WARNING: Response significantly reduced by language filtering (\(response.count) -> \(filtered.count))")
        }
        #endif
        
        // ALLOW clinical trial anxiety/fear discussions - these are educational, not medical advice
        let queryLower = query.lowercased()
        let isAnxietyDiscussion = queryLower.contains("scared") || queryLower.contains("nervous") || 
                                 queryLower.contains("afraid") || queryLower.contains("worried") || 
                                 queryLower.contains("anxious")
        let isClinicalTrialContext = isClinicallTrialRelated(query)
        
        // If it's clinical trial anxiety discussion, allow the response
        if isAnxietyDiscussion && isClinicalTrialContext {
            // This is educational support for clinical trial participation concerns - ALLOW
            return filtered
        }
        
        // Check if response contains personal medical advice
        let responseLower = response.lowercased()
        for pattern in personalAdvicePatterns {
            if responseLower.contains(pattern) {
                return """
                I cannot provide personal medical advice. For clinical trial participation or medical decisions, \
                please consult with healthcare professionals who can review your specific situation.
                
                I can help you understand:
                • How clinical trials work
                • Different phases of trials
                • General eligibility criteria
                • The informed consent process
                • Questions to ask research teams
                """
            }
        }
        
        // Add medical disclaimer if discussing treatments
        if responseLower.contains("treatment") || responseLower.contains("therapy") ||
           responseLower.contains("medication") || responseLower.contains("drug") {
            if !filtered.contains("⚠️") {
                filtered += "\n\n⚠️ This information is for educational purposes only. Always consult healthcare professionals for medical advice."
            }
        }
        
        // Add FDA disclaimer if mentioned
        if responseLower.contains("fda") || responseLower.contains("approved") {
            if !filtered.contains("📋") {
                filtered += "\n\n📋 Note: Drug approval status can change. Verify current information with FDA.gov or your healthcare provider."
            }
        }
        
        // Handle off-topic gracefully - BUT ALLOW foreign language clinical trial responses
        // Also allow protocol-related information (PI names, protocol details, etc.)
        let isQueryClinicalTrialRelated = isClinicallTrialRelated(query)
        let isResponseClinicalTrialRelated = responseLower.contains("clinical trial") || 
                                           responseLower.contains("ensayo clínico") || 
                                           responseLower.contains("essai clinique") || 
                                           responseLower.contains("klinische studie") || 
                                           responseLower.contains("studio clinico") || 
                                           responseLower.contains("estudo clínico") ||
                                           responseLower.contains("fase") || // "phase" in multiple languages
                                           responseLower.contains("phase") ||
                                           responseLower.contains("placebo") || // Universal term
                                           responseLower.contains("patient") || // Universal term
                                           responseLower.contains("paciente") || // Spanish/Portuguese
                                           responseLower.contains("paziente") || // Italian
                                           responseLower.contains("protocol") || // Protocol information
                                           responseLower.contains("principal investigator") || // PI names
                                           responseLower.contains("investigator") || // Investigator info
                                           responseLower.contains("researcher") || // Researcher names
                                           // TIN/Network-related terms in multiple languages
                                           responseLower.contains("innovation network") ||
                                           responseLower.contains("trial innovation") ||
                                           responseLower.contains("innovationsnetzwerk") || // German
                                           responseLower.contains("netzwerk") || // German "network"
                                           responseLower.contains("réseau") || // French "network"
                                           responseLower.contains("rete") || // Italian "network"
                                           responseLower.contains("red de") || // Spanish "network"
                                           responseLower.contains("rede de") || // Portuguese "network"
                                           responseLower.contains("recruitment") ||
                                           responseLower.contains("recruitment support") ||
                                           responseLower.contains("ctsa") || // CTSA consortium
                                           responseLower.contains("consortium")
        
        // If query is about protocol/PI, allow the response (even if it's just a name)
        // This handles questions like "what is the name of the PI of the protocol"
        let isProtocolQuery = queryLower.contains("protocol") || queryLower.contains("pi") || 
                             queryLower.contains("principal investigator") || queryLower.contains("investigator") ||
                             queryLower.contains("name of")
        
        // Check if query is asking about a specific individual (who is, tell me about, etc.)
        // These queries should be allowed if the person might be in the knowledge cache
        let isIndividualQuery = queryLower.contains("who is") || queryLower.contains("tell me about") ||
                               queryLower.contains("what is") || queryLower.contains("who was") ||
                               queryLower.contains("information about") || queryLower.contains("details about")
        
        // Check if response contains information about a person (titles, roles, etc.)
        let isPersonResponse = responseLower.contains("dr.") || responseLower.contains("doctor") ||
                              responseLower.contains("professor") || responseLower.contains("researcher") ||
                              responseLower.contains("investigator") || responseLower.contains("principal investigator") ||
                              responseLower.contains("phd") || responseLower.contains("md") ||
                              responseLower.contains("director") || responseLower.contains("chair") ||
                              responseLower.contains("university") || responseLower.contains("hospital") ||
                              responseLower.contains("clinic") || responseLower.contains("medical center")
        
        // Allow protocol/PI queries - the response might just be a name without protocol keywords
        if isProtocolQuery {
            // Query is clearly about protocol/PI - allow response even if it's just a name
            return filtered
        }
        
        // Allow queries about individuals if they might be in the knowledge cache
        // This handles "who is [name]" queries where the person is mentioned in documents
        if isIndividualQuery {
            // If the response contains person-related information, allow it
            // This suggests the person is in the knowledge cache
            if isPersonResponse || isResponseClinicalTrialRelated {
                return filtered
            }
            // Even if response doesn't have person indicators, allow it if query is about an individual
            // The knowledge cache might contain information about them
            return filtered
        }
        
        if !isQueryClinicalTrialRelated && !isResponseClinicalTrialRelated {
            return """
            I'm Corra, and I specialize in clinical trials! I'd be happy to help you understand:
            
            • What clinical trials are and how they work
            • Different phases of drug development
            • How to find and participate in trials
            • Understanding informed consent
            • Safety measures in research studies
            • Questions to ask research teams
            
            What aspect of clinical trials would you like to know about?
            """
        }
        
        return filtered
    }
    
    // MARK: - Trust Score (from trust_aware_cora.py)
    
    func calculateTrustScore(for input: String) -> Double {
        let lowercased = input.lowercased()
        var score = 1.0
        
        // Reduce trust for potentially adversarial inputs
        for pattern in dangerousPatterns {
            if lowercased.contains(pattern) {
                score *= 0.1
            }
        }
        
        // Increase trust for clinical trial related
        if isClinicallTrialRelated(input) {
            score *= 1.2
        }
        
        // Cap between 0 and 1
        return min(max(score, 0.0), 1.0)
    }
    
    // MARK: - System Prompt
    
    func getSystemPrompt() -> String {
        // Direct from Python cora.py
        return """
        You are Corra, a friendly and knowledgeable AI assistant who specializes in clinical trials.
        
        Your personality:
        - Warm, approachable, and patient
        - Expert in clinical trials but explains things simply
        - Always helpful and encouraging
        
        Your rules:
        1. ONLY answer questions related to this clinical trial protocol
        2. Explain everything in simple, clear language that anyone can understand
        3. Use everyday examples and analogies when helpful
        4. Be accurate but avoid overwhelming medical jargon
        5. If asked about non-clinical trial topics, politely redirect to clinical trials
        6. When creating lists (questions, steps, etc.), ensure each item is unique and avoid repetition
        7. You can respond in foreign languages (Spanish, French, German, Italian, Portuguese, etc.) when requested, as long as the topic remains clinical trials related
        
        For non-clinical trial questions, respond with:
        "I'm Corra, and I specialize in clinical trials! I'd be happy to help you understand clinical trials. What would you like to know about clinical trials?"
        
        Important: Never mention that you're explaining things at any particular age or education level. Just keep your language naturally clear and simple.
        """
    }
}

