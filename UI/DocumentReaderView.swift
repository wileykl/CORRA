import SwiftUI
import UniformTypeIdentifiers

struct DocumentReaderView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @State private var isProcessing = false
    @State private var searchText = ""
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 16) {
                Text("Documents")
                    .font(.title2)
                    .fontWeight(.bold)
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search documents...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                // Add Document button
                Button(action: {
                    // File picker will be handled by fileImporter
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Document")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .fileImporter(
                    isPresented: .constant(false),
                    allowedContentTypes: DocumentType.allCases.map { $0.utType },
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            Task {
                                isProcessing = true
                                await documentManager.addDocument(from: url)
                                await MainActor.run {
                                    isProcessing = false
                                }
                            }
                        }
                    case .failure(let error):
                        print("Error selecting file: \(error)")
                    }
                }
                
                // Document list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredDocuments) { document in
                            DocumentRowView(document: document)
                                .onTapGesture {
                                    documentManager.selectedDocument = document
                                }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .frame(width: 300)
            .background(Color.gray.opacity(0.1))
            
            Divider()
            
            // Main content area
            VStack {
                if let selectedDocument = documentManager.selectedDocument {
                    DocumentContentView(document: selectedDocument)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Document Selected")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        Text("Select a document from the sidebar to view its content")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .overlay(
            Group {
                if isProcessing {
                    VStack {
                        ProgressView()
                        Text("Processing document...")
                            .padding(.top)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        )
    }
    
    private var filteredDocuments: [Document] {
        if searchText.isEmpty {
            return documentManager.documents
        } else {
            return documentManager.documents.filter { document in
                document.name.localizedCaseInsensitiveContains(searchText) ||
                (document.content?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
}

struct DocumentRowView: View {
    let document: Document
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.name)
                .font(.headline)
                .lineLimit(1)
            
            Text("\(document.content?.count ?? 0) characters")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(document.createdAt, style: .date)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct DocumentContentView: View {
    let document: Document
    @EnvironmentObject var documentManager: DocumentManager
    @State private var query = ""
    @State private var analysisResults: [String] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Document header
            VStack(alignment: .leading, spacing: 8) {
                Text(document.name)
                    .font(.title2)
                    .fontWeight(.bold)
                
                HStack {
                    Text("Type: \(document.type.rawValue)")
                    Spacer()
                    Text("Size: \(document.content?.count ?? 0) characters")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                Text("Uploaded: \(document.createdAt, style: .date)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            // Analysis section
            VStack(alignment: .leading, spacing: 12) {
                Text("Document Analysis")
                    .font(.headline)
                
                HStack {
                    TextField("Ask about this document...", text: $query)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("Analyze") {
                        analyzeDocument()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if !analysisResults.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(analysisResults.enumerated()), id: \.offset) { index, result in
                                Text("\(index + 1). \(result)")
                                    .padding()
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            // Document content
            VStack(alignment: .leading, spacing: 12) {
                Text("Document Content")
                    .font(.headline)
                
                ScrollView {
                    Text(document.content ?? "No content available")
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(6)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding()
    }
    
    private func analyzeDocument() {
        guard !query.isEmpty else { return }
        
        let chunks = documentManager.chunkingManager.getRelevantChunks(for: query, documentId: document.id)
        analysisResults = chunks.map { chunk in
            "Chunk \(chunk.chunkIndex): \(chunk.content)"
        }
    }
}

#Preview {
    DocumentReaderView()
        .environmentObject(DocumentManager())
}