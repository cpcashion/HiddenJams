//
//  OpenAIService.swift
//  HiddenJams
//
//  Service for interacting with OpenAI API (Embeddings & Chat)
//

import Foundation
import Combine

class OpenAIService: ObservableObject {
    private var apiKey: String { APIConfiguration.openAIAPIKey }
    private let baseURL = "https://api.openai.com/v1"
    
    init() {}
    
    // MARK: - Embeddings
    
    func generateEmbedding(text: String) async throws -> [Double] {
        let url = URL(string: "\(baseURL)/embeddings")!
        let body: [String: Any] = [
            "input": text,
            "model": "text-embedding-3-small"
        ]
        
        let response: EmbeddingResponse = try await makeRequest(url: url, body: body)
        
        guard let embedding = response.data.first?.embedding else {
            throw OpenAIError.invalidResponse
        }
        
        return embedding
    }
    
    func generateEmbeddings(texts: [String]) async throws -> [[Double]] {
        // OpenAI allows batching, but let's keep it safe with chunks of 20
        var allEmbeddings: [[Double]] = []
        
        for chunk in texts.chunked(into: 20) {
            let url = URL(string: "\(baseURL)/embeddings")!
            let body: [String: Any] = [
                "input": chunk,
                "model": "text-embedding-3-small"
            ]
            
            let response: EmbeddingResponse = try await makeRequest(url: url, body: body)
            let chunkEmbeddings = response.data.sorted { $0.index < $1.index }.map { $0.embedding }
            allEmbeddings.append(contentsOf: chunkEmbeddings)
        }
        
        return allEmbeddings
    }
    
    // MARK: - Chat Completion (Taste Profile)
    
    func generateTasteProfile(stats: String) async throws -> String {
        let systemPrompt = """
        You are a sophisticated music critic and taste analyst. 
        Analyze the user's listening statistics and describe their specific musical taste in 3-4 short, engaging paragraphs.
        Focus on the "vibe", specific sub-genres, and lyrical themes they seem to prefer.
        Avoid generic phrases like "you like music". Be specific, slightly witty, and insightful.
        Also provide 5 "Superpowers" (bullet points) describing their unique listening traits.
        """
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": stats]
            ],
            "temperature": 0.7
        ]
        
        let response: ChatCompletionResponse = try await makeRequest(url: url, body: body)
        return response.choices.first?.message.content ?? "Could not generate profile."
    }
    
    // MARK: - Helpers
    
    private func makeRequest<T: Decodable>(url: URL, body: [String: Any]) async throws -> T {
        guard !apiKey.isEmpty else { throw OpenAIError.missingApiKey }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.networkError
        }
        
        if httpResponse.statusCode != 200 {
            print("OpenAI Error: \(httpResponse.statusCode)")
            if let errorText = String(data: data, encoding: .utf8) {
                print("Response: \(errorText)")
            }
            throw OpenAIError.apiError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Models

struct EmbeddingResponse: Codable {
    let data: [EmbeddingData]
}

struct EmbeddingData: Codable {
    let embedding: [Double]
    let index: Int
}

struct ChatCompletionResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: Message
}

struct Message: Codable {
    let content: String
}

enum OpenAIError: Error, LocalizedError {
    case missingApiKey
    case networkError
    case apiError(Int)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .missingApiKey: return "OpenAI API key is not configured. See SETUP.md."
        case .networkError: return "Network connection failed."
        case .apiError(let code): return "OpenAI API Error (Code: \(code))"
        case .invalidResponse: return "Invalid response from OpenAI."
        }
    }
}
