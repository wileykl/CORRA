import Foundation
import Combine
import PDFKit
import UniformTypeIdentifiers

// MARK: - Document Model
struct Document: Identifiable, Codable {
    let id: UUID
    let name: String
    let url: URL
    let type: DocumentType
    let size: Int64
    let createdAt: Date
    var content: String?
    var isProcessed: Bool = false
    
    init(name: String, url: URL, type: DocumentType, size: Int64) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.type = type
        self.size = size
        self.createdAt = Date()
    }
}

// MARK: - Document Type
enum DocumentType: String, CaseIterable, Codable {
    case pdf = "pdf"
    case docx = "docx"
    case txt = "txt"
    case md = "md"
    case rtf = "rtf"
    case xlsx = "xlsx"
    
    var utType: UTType {
        switch self {
        case .pdf:
            return .pdf
        case .docx:
            return UTType(filenameExtension: "docx") ?? .data
        case .txt:
            return .plainText
        case .md:
            return UTType(filenameExtension: "md") ?? .plainText
        case .rtf:
            return .rtf
        case .xlsx:
            return UTType(filenameExtension: "xlsx") ?? .spreadsheet
        }
    }
    
    var displayName: String {
        switch self {
        case .pdf: return "PDF Document"
        case .docx: return "Word Document"
        case .txt: return "Text File"
        case .md: return "Markdown File"
        case .rtf: return "Rich Text File"
        case .xlsx: return "Excel Spreadsheet"
        }
    }
}

// MARK: - Document Manager
class DocumentManager: ObservableObject {
    @Published var documents: [Document] = []
    @Published var selectedDocument: Document?
    
    let chunkingManager = DocumentChunkingManager.shared
    
    init() {
        loadDocuments()
    }
    
    // MARK: - Document Management
    func addDocument(from url: URL) async {
        do {
            // Start accessing security-scoped resource
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            let fileName = url.lastPathComponent
            let fileExtension = url.pathExtension.lowercased()
            
            guard let documentType = DocumentType(rawValue: fileExtension) else {
                #if DEBUG
                print("Unsupported file type: \(fileExtension)")
                #endif
                return
            }
            
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = fileAttributes[.size] as? Int64 ?? 0
            
            let document = Document(
                name: fileName,
                url: url,
                type: documentType,
                size: fileSize
            )
            
            // Process document content
            let content = await processDocument(url: url, type: documentType)
            #if DEBUG
            print("🔍 DEBUG: Document content processed: \(content.count) characters")
            #endif
            
            var processedDocument = document
            processedDocument.content = content
            processedDocument.isProcessed = true
            
            await MainActor.run {
                self.documents.append(processedDocument)
                self.selectedDocument = processedDocument  // Automatically select the uploaded document
                self.saveDocuments()
                #if DEBUG
                print("🔍 DEBUG: Created document: \(processedDocument.name), chunks: \(self.documents.count) total")
                #endif
            }
            
            // Chunk the document
            let chunks = chunkingManager.chunkDocument(processedDocument)
            #if DEBUG
            print("Created \(chunks.count) chunks for document: \(fileName)")
            #endif
            
        } catch {
            #if DEBUG
            print("Error adding document: \(error)")
            #endif
        }
    }
    
    func removeDocument(_ document: Document) {
        documents.removeAll { $0.id == document.id }
        if selectedDocument?.id == document.id {
            selectedDocument = nil
        }
        
        // Remove chunks for this document
        chunkingManager.removeChunksForDocument(document.id)
        
        saveDocuments()
    }
    
    func searchDocuments(query: String) -> [Document] {
        if query.isEmpty {
            return documents
        }
        
        return documents.filter { document in
            document.name.localizedCaseInsensitiveContains(query) ||
            document.type.displayName.localizedCaseInsensitiveContains(query) ||
            (document.content?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
    
    // MARK: - Document Processing
    private func processDocument(url: URL, type: DocumentType) async -> String {
        do {
            switch type {
            case .pdf:
                return await processPDFDocument(url: url)
            case .docx:
                return await processDOCXDocument(url: url)
            case .txt, .md, .rtf:
                return await processTextDocument(url: url)
            case .xlsx:
                return await processExcelDocument(url: url)
            }
        } catch {
            return "Error processing document: \(error.localizedDescription)"
        }
    }
    
    private func processPDFDocument(url: URL) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let pdfDocument = PDFDocument(url: url)
                    var text = ""
                    
                    if let pdfDoc = pdfDocument {
                        for pageIndex in 0..<pdfDoc.pageCount {
                            if let page = pdfDoc.page(at: pageIndex) {
                                if let pageText = page.string {
                                    text += pageText + "\n"
                                }
                            }
                        }
                    }
                    
                    continuation.resume(returning: text.isEmpty ? "Could not extract text from PDF" : text)
                } catch {
                    continuation.resume(returning: "Error reading PDF: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func processDOCXDocument(url: URL) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // For now, return a placeholder - DOCX processing would require additional libraries
                continuation.resume(returning: "DOCX processing not yet implemented. Content extraction requires additional libraries.")
            }
        }
    }
    
    private func processTextDocument(url: URL) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    continuation.resume(returning: content)
                } catch {
                    // Try different encodings
                    let encodings: [String.Encoding] = [.utf8, .ascii, .isoLatin1, .windowsCP1252]
                    for encoding in encodings {
                        do {
                            let content = try String(contentsOf: url, encoding: encoding)
                            continuation.resume(returning: content)
                            return
                        } catch {
                            continue
                        }
                    }
                    continuation.resume(returning: "Error reading text file: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func processExcelDocument(url: URL) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // For now, return a placeholder - Excel processing would require additional libraries
                continuation.resume(returning: "Excel processing not yet implemented. Content extraction requires additional libraries.")
            }
        }
    }
    
    // MARK: - Document Context for AI (Replicating Web App Logic)
    func getDocumentContextForQuery(_ query: String) -> String {
        guard let selectedDoc = selectedDocument else {
            return ""
        }
        
        guard let content = selectedDoc.content, !content.isEmpty else {
            return ""
        }
        
        #if DEBUG
        print("DEBUG: getDocumentContextForQuery - document: \(selectedDoc.name), content length: \(content.count)")
        #endif
        
        // Replicate the web app's get_document_context function exactly
        var context = "\n\n--- UPLOADED DOCUMENTS CONTEXT ---\n"
        context += "The user has uploaded the following documents that you can reference:\n\n"
        
        // Document metadata (replicating web app format)
        context += "Document: \(selectedDoc.name)\n"
        context += "Uploaded: \(selectedDoc.createdAt)\n"
        context += "Type: \(selectedDoc.type.rawValue)\n"
        context += "Size: \(content.split(separator: " ").count) words\n"
        
        // Search for relevant content using web app's method
        let relevantContent = searchDocumentContent(query: query, documentContent: content, maxResults: 5)
        
        if !relevantContent.isEmpty {
            context += "RELEVANT CONTENT (based on your question):\n"
            for (index, content) in relevantContent.enumerated() {
                context += "\(index + 1). \(content)\n\n"
            }
        } else {
            // Fallback to first 300 words if no specific matches
            let contentWords = content.split(separator: " ").prefix(300)
            let contentPreview = contentWords.joined(separator: " ")
            if content.split(separator: " ").count > 300 {
                context += "Content Preview:\n\(contentPreview)... [content truncated - ask specific questions for full search]\n"
            } else {
                context += "Content Preview:\n\(contentPreview)\n"
            }
        }
        
        context += "---\n\n"
        context += "IMPORTANT: This shows relevant excerpts from the most relevant document. For comprehensive analysis, use the document analysis feature.\n"
        
        #if DEBUG
        print("🔍 DEBUG: Generated context length: \(context.count)")
        #endif
        
        return context
    }
    
    func getSelectedDocumentContextForQuery(_ query: String) -> String {
        return getDocumentContextForQuery(query)
    }
    
    // Implement the web app's intelligent document search (exact replication)
    private func searchDocumentContent(query: String, documentContent: String, maxResults: Int = 3) -> [String] {
        let queryLower = query.lowercased()
        let queryTerms = queryLower.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { $0.count > 2 }
        
        #if DEBUG
        print("🔍 DEBUG: Extracted \(queryTerms.count) query terms")
        #endif
        
        // Split into paragraphs first, then sentences within paragraphs
        let paragraphs = documentContent.components(separatedBy: "\n\n")
        var relevantSections: [(Double, String)] = []
        
        for paragraph in paragraphs {
            let paragraphLower = paragraph.lowercased()
            
            // Check if paragraph contains query terms
            let matches = queryTerms.reduce(0) { count, term in
                count + (paragraphLower.contains(term) ? 1 : 0)
            }
            
            if matches > 0 {
                // Split paragraph into sentences more intelligently
                let sentences = paragraph.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                
                for i in 0..<sentences.count {
                    let sentence = sentences[i]
                    let sentenceLower = sentence.lowercased()
                    let sentenceMatches = queryTerms.reduce(0) { count, term in
                        count + (sentenceLower.contains(term) ? 1 : 0)
                    }
                    
                    if sentenceMatches > 0 {
                        // Include context: get surrounding sentences from the paragraph
                        let startIdx = max(0, i - 1)
                        let endIdx = min(sentences.count, i + 3)
                        let contextSentences = Array(sentences[startIdx..<endIdx])
                        let relevantText = contextSentences.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if !relevantText.isEmpty && relevantText.count > 50 {
                            // Score by number of matching terms and length
                            let score = Double(sentenceMatches) * 10.0 + min(Double(relevantText.count), 500.0) / 100.0
                            relevantSections.append((score, relevantText))
                        }
                    }
                }
            }
        }
        
        // Sort by relevance score and return top results
        relevantSections.sort { $0.0 > $1.0 }
        let topResults = relevantSections.prefix(maxResults).map { $0.1 }
        
        #if DEBUG
        print("DEBUG: Found \(topResults.count) relevant sections")
        #endif
        return Array(topResults)
    }
    
    // Extract meaningful terms from query (similar to web app)
    private func extractQueryTerms(from query: String) -> [String] {
        let stopWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "is", "are", "was", "were", "be", "been", "have", "has", "had", "do", "does", "did", "will", "would", "could", "should", "may", "might", "can", "what", "where", "when", "why", "how", "who", "which", "this", "that", "these", "those"])
        
        return query.lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { word in
                word.count > 2 && !stopWords.contains(word)
            }
    }
    
    // MARK: - Persistence
    private func saveDocuments() {
        do {
            let data = try JSONEncoder().encode(documents)
            UserDefaults.standard.set(data, forKey: "SavedDocuments")
        } catch {
            #if DEBUG
            print("Error saving documents: \(error)")
            #endif
        }
    }
    
    private func loadDocuments() {
        guard let data = UserDefaults.standard.data(forKey: "SavedDocuments") else {
            return
        }
        
        do {
            documents = try JSONDecoder().decode([Document].self, from: data)
        } catch {
            #if DEBUG
            print("Error loading documents: \(error)")
            #endif
        }
    }
}

// MARK: - UTType Extension
extension UTType {
    static var supportedDocumentTypes: [UTType] {
        return [
            .pdf,
            .plainText,
            .rtf,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "xlsx") ?? .spreadsheet
        ]
    }
}
