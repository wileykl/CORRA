import Foundation
import Combine

// MARK: - Document Chunk Model
struct DocumentChunk: Identifiable, Codable {
    let id = UUID()
    let documentId: UUID
    let content: String
    let chunkIndex: Int
    let startPosition: Int
    let endPosition: Int
    let metadata: [String: String]
    let createdAt: Date
    
    init(documentId: UUID, content: String, chunkIndex: Int, startPosition: Int, endPosition: Int, metadata: [String: String] = [:]) {
        self.documentId = documentId
        self.content = content
        self.chunkIndex = chunkIndex
        self.startPosition = startPosition
        self.endPosition = endPosition
        self.metadata = metadata
        self.createdAt = Date()
    }
}

// MARK: - Document Chunking Manager
class DocumentChunkingManager: ObservableObject {
    static let shared = DocumentChunkingManager()
    
    @Published var chunks: [DocumentChunk] = []
    
    private let maxChunkSize = 1000 // Maximum characters per chunk
    private let overlapSize = 100   // Overlap between chunks for context
    
    private init() {}
    
    // MARK: - Chunking Methods
    func chunkDocument(_ document: Document) -> [DocumentChunk] {
        guard let content = document.content, !content.isEmpty else {
            print("⚠️ No content to chunk for document: \(document.name)")
            return []
        }
        
        print("📄 Chunking document: \(document.name) (\(content.count) characters)")
        
        let chunks = createChunks(
            content: content,
            documentId: document.id,
            maxChunkSize: maxChunkSize,
            overlapSize: overlapSize
        )
        
        print("✅ Created \(chunks.count) chunks for document: \(document.name)")
        
        // Store chunks
        self.chunks.append(contentsOf: chunks)
        
        return chunks
    }
    
    private func createChunks(
        content: String,
        documentId: UUID,
        maxChunkSize: Int,
        overlapSize: Int
    ) -> [DocumentChunk] {
        var chunks: [DocumentChunk] = []
        let sentences = splitIntoSentences(content)
        
        var currentChunk = ""
        var currentStart = 0
        var chunkIndex = 0
        
        for (index, sentence) in sentences.enumerated() {
            // Check if adding this sentence would exceed max chunk size
            if currentChunk.count + sentence.count > maxChunkSize && !currentChunk.isEmpty {
                // Create chunk from current content
                let chunk = DocumentChunk(
                    documentId: documentId,
                    content: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines),
                    chunkIndex: chunkIndex,
                    startPosition: currentStart,
                    endPosition: currentStart + currentChunk.count,
                    metadata: [
                        "sentence_count": "\(sentences.prefix(index).count)",
                        "chunk_type": "content"
                    ]
                )
                chunks.append(chunk)
                
                // Start new chunk with overlap
                let overlapText = String(currentChunk.suffix(overlapSize))
                currentChunk = overlapText + " " + sentence
                currentStart = currentStart + currentChunk.count - overlapSize - sentence.count
                chunkIndex += 1
            } else {
                currentChunk += (currentChunk.isEmpty ? "" : " ") + sentence
            }
        }
        
        // Add final chunk if there's remaining content
        if !currentChunk.isEmpty {
            let chunk = DocumentChunk(
                documentId: documentId,
                content: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines),
                chunkIndex: chunkIndex,
                startPosition: currentStart,
                endPosition: currentStart + currentChunk.count,
                metadata: [
                    "sentence_count": "\(sentences.count)",
                    "chunk_type": "content"
                ]
            )
            chunks.append(chunk)
        }
        
        return chunks
    }
    
    private func splitIntoSentences(_ text: String) -> [String] {
        // Simple sentence splitting - can be enhanced with more sophisticated NLP
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        return sentences
    }
    
    // MARK: - Search and Retrieval
    func searchChunks(query: String, documentId: UUID? = nil) -> [DocumentChunk] {
        let searchQuery = query.lowercased()
        
        // Extract meaningful keywords from the query
        let keywords = extractKeywords(from: searchQuery)
        print("🔍 DEBUG: searchChunks - query: '\(query)', keywords: \(keywords)")
        
        return chunks.filter { chunk in
            // Filter by document if specified
            if let documentId = documentId, chunk.documentId != documentId {
                return false
            }
            
            // If no meaningful keywords, return all chunks (for general queries like "summarize")
            if keywords.isEmpty {
                return true
            }
            
            // Search for any of the keywords in content
            let contentLower = chunk.content.lowercased()
            return keywords.contains { keyword in
                contentLower.contains(keyword)
            }
        }
        .sorted { chunk1, chunk2 in
            // Sort by relevance score
            let score1 = calculateRelevanceScore(chunk1.content, query: searchQuery, keywords: keywords)
            let score2 = calculateRelevanceScore(chunk2.content, query: searchQuery, keywords: keywords)
            return score1 > score2
        }
    }
    
    private func extractKeywords(from query: String) -> [String] {
        // Remove common stop words and extract meaningful keywords
        let stopWords = Set([
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by",
            "is", "are", "was", "were", "be", "been", "being", "have", "has", "had", "do", "does", "did",
            "will", "would", "could", "should", "may", "might", "can", "must", "shall",
            "this", "that", "these", "those", "i", "you", "he", "she", "it", "we", "they",
            "me", "him", "her", "us", "them", "my", "your", "his", "her", "its", "our", "their",
            "what", "when", "where", "why", "how", "who", "which", "whom", "whose",
            "summarize", "summary", "overview", "describe", "explain", "tell", "about",
            "document", "file", "uploaded", "upload", "uploaded", "document"
        ])
        
        let words = query.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && $0.count > 2 }
            .filter { !stopWords.contains($0.lowercased()) }
        
        return words
    }
    
    private func calculateRelevanceScore(_ content: String, query: String, keywords: [String]) -> Int {
        let contentLower = content.lowercased()
        
        var score = 0
        
        // If no keywords, give a base score for general queries
        if keywords.isEmpty {
            // For general queries like "summarize", prioritize chunks with more content
            return content.count / 100
        }
        
        // Score based on keyword matches
        for keyword in keywords {
            if contentLower.contains(keyword) {
                score += 1
                
                // Bonus for multiple occurrences
                let occurrences = contentLower.components(separatedBy: keyword).count - 1
                score += min(occurrences, 3) // Cap bonus at 3
            }
        }
        
        // Bonus for chunks that appear earlier in the document (likely more important)
        if let chunk = chunks.first(where: { $0.content == content }) {
            score += max(0, 100 - chunk.chunkIndex) // Earlier chunks get higher scores
        }
        
        return score
    }
    
    func getChunksForDocument(_ documentId: UUID) -> [DocumentChunk] {
        return chunks.filter { $0.documentId == documentId }
            .sorted { $0.chunkIndex < $1.chunkIndex }
    }
    
    func getRelevantChunks(for query: String, documentId: UUID, limit: Int = 3) -> [DocumentChunk] {
        print("🔍 Searching for query '\(query)' in document \(documentId)")
        print("📚 Total chunks available: \(chunks.count)")
        print("📄 Chunks for this document: \(chunks.filter { $0.documentId == documentId }.count)")
        
        let relevantChunks = searchChunks(query: query, documentId: documentId)
        print("✅ Found \(relevantChunks.count) relevant chunks")
        
        // If no relevant chunks found, return the first few chunks for general queries
        let result: [DocumentChunk]
        if relevantChunks.isEmpty {
            print("⚠️ No relevant chunks found, returning first \(limit) chunks for general query")
            let documentChunks = chunks.filter { $0.documentId == documentId }
                .sorted { $0.chunkIndex < $1.chunkIndex }
            result = Array(documentChunks.prefix(limit))
        } else {
            result = Array(relevantChunks.prefix(limit))
        }
        
        print("📝 Returning \(result.count) chunks (limit: \(limit))")
        
        return result
    }
    
    // MARK: - Cleanup
    func removeChunksForDocument(_ documentId: UUID) {
        chunks.removeAll { $0.documentId == documentId }
    }
    
    func clearAllChunks() {
        chunks.removeAll()
    }
}

extension CharacterSet {
    static var sentences: CharacterSet {
        var set = CharacterSet()
        set.insert(charactersIn: ".!?")
        return set
    }
}
