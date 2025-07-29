import Foundation

/// Google Gemini provider implementing the AIProvider protocol
/// Supports Gemini models with multimodal capabilities
@MainActor
class GeminiProvider: ExternalAPIProvider {
    
    // MARK: - AIProvider Implementation
    
    override var providerId: String { "google_gemini" }
    override var displayName: String { "Google Gemini" }
    
    // MARK: - Gemini Configuration
    
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    private let userAgent = "Web-Browser/1.0"
    
    // MARK: - Rate Limiting
    
    private var lastRequestTime: Date = Date.distantPast
    private let minimumRequestInterval: TimeInterval = 0.1 // 10 requests per second max
    
    init() {
        super.init(apiProviderType: .gemini)
    }
    
    // MARK: - Model Management
    
    override func loadAvailableModels() async {
        availableModels = [
            AIModel(
                id: "gemini-2.0-flash-exp",
                name: "Gemini 2.0 Flash",
                description: "Latest Gemini model with advanced multimodal capabilities",
                contextWindow: 1048576, // 1M tokens
                costPerToken: 0.000001, // $1 per 1M tokens (approximate)
                capabilities: [.textGeneration, .conversation, .summarization, .codeGeneration, .imageAnalysis, .functionCalling],
                provider: providerId,
                isAvailable: true
            ),
            AIModel(
                id: "gemini-1.5-pro",
                name: "Gemini 1.5 Pro",
                description: "Most capable Gemini 1.5 model with large context window",
                contextWindow: 2097152, // 2M tokens
                costPerToken: 0.00000125, // $1.25 per 1M tokens (approximate)
                capabilities: [.textGeneration, .conversation, .summarization, .codeGeneration, .imageAnalysis, .functionCalling],
                provider: providerId,
                isAvailable: true
            ),
            AIModel(
                id: "gemini-1.5-flash",
                name: "Gemini 1.5 Flash",
                description: "Fast and efficient Gemini model for quick responses",
                contextWindow: 1048576, // 1M tokens
                costPerToken: 0.000000375, // $0.375 per 1M tokens (approximate)
                capabilities: [.textGeneration, .conversation, .summarization, .codeGeneration, .imageAnalysis],
                provider: providerId,
                isAvailable: true
            )
        ]
        
        // Set default model
        if selectedModel == nil {
            selectedModel = availableModels.first { $0.id == "gemini-2.0-flash-exp" } ?? availableModels.first
        }
        
        NSLog("📋 Loaded \(availableModels.count) Gemini models")
    }
    
    // MARK: - Configuration Validation
    
    override func validateConfiguration() async throws {
        guard apiKey != nil else {
            throw AIProviderError.missingAPIKey(displayName)
        }
        
        // Test API key with a simple request
        let modelName = "gemini-1.5-flash"
        let testPayload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": "Hi"]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 5
            ]
        ]
        
        do {
            let _ = try await makeAPIRequest(
                endpoint: "/models/\(modelName):generateContent",
                payload: testPayload
            )
            NSLog("✅ Gemini API key validated")
        } catch {
            throw AIProviderError.authenticationFailed
        }
    }
    
    // MARK: - Core AI Methods
    
    override func generateResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        model: AIModel?
    ) async throws -> AIResponse {
        let startTime = Date()
        let modelId = model?.id ?? selectedModel?.id ?? "gemini-2.0-flash-exp"
        
        // Apply rate limiting
        await applyRateLimit()
        
        // Build contents
        let contents = buildContents(query: query, context: context, history: conversationHistory)
        
        var payload: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": 4096,
                "temperature": 0.7,
                "topP": 0.9,
                "topK": 40
            ],
            "safetySettings": [
                [
                    "category": "HARM_CATEGORY_HARASSMENT",
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ],
                [
                    "category": "HARM_CATEGORY_HATE_SPEECH",
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ],
                [
                    "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ],
                [
                    "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ]
            ]
        ]
        
        // Add system instruction if we have context
        if let context = context, !context.isEmpty {
            payload["systemInstruction"] = [
                "parts": [
                    ["text": "You are a helpful assistant. Answer questions based on the provided webpage content:\n\n\(context)"]
                ]
            ]
        }
        
        do {
            let response = try await makeAPIRequest(
                endpoint: "/models/\(modelId):generateContent",
                payload: payload
            )
            
            guard let candidates = response["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let firstPart = parts.first,
                  let text = firstPart["text"] as? String else {
                throw AIProviderError.providerSpecificError("Invalid response format from Gemini")
            }
            
            // Extract usage information
            var tokenCount = 0
            var cost: Double? = nil
            
            if let usageMetadata = response["usageMetadata"] as? [String: Any] {
                let promptTokens = usageMetadata["promptTokenCount"] as? Int ?? 0
                let outputTokens = usageMetadata["candidatesTokenCount"] as? Int ?? 0
                tokenCount = promptTokens + outputTokens
                
                if let modelInfo = availableModels.first(where: { $0.id == modelId }),
                   let costPerToken = modelInfo.costPerToken {
                    cost = Double(tokenCount) * costPerToken
                }
            }
            
            let responseTime = Date().timeIntervalSince(startTime)
            updateUsageStats(
                tokenCount: tokenCount,
                responseTime: responseTime,
                cost: cost,
                error: false
            )
            
            // Create metadata for external API response
            let metadata = ResponseMetadata(
                modelVersion: modelId,
                inferenceMethod: .fallback,
                contextUsed: context != nil,
                processingSteps: [],
                memoryUsage: 0,
                energyImpact: responseTime > 5.0 ? .moderate : .low
            )
            
            // Return AIResponse compatible with existing system
            return AIResponse(
                text: text,
                processingTime: responseTime,
                tokenCount: tokenCount,
                metadata: metadata
            )
            
        } catch {
            let responseTime = Date().timeIntervalSince(startTime)
            updateUsageStats(tokenCount: 0, responseTime: responseTime, error: true)
            throw handleAPIError(error)
        }
    }
    
    override func generateStreamingResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        model: AIModel?
    ) async throws -> AsyncThrowingStream<String, Error> {
        let modelId = model?.id ?? selectedModel?.id ?? "gemini-2.0-flash-exp"
        
        // Apply rate limiting
        await applyRateLimit()
        
        // Build contents
        let contents = buildContents(query: query, context: context, history: conversationHistory)
        
        var payload: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": 4096,
                "temperature": 0.7,
                "topP": 0.9,
                "topK": 40
            ]
        ]
        
        // Add system instruction if we have context
        if let context = context, !context.isEmpty {
            payload["systemInstruction"] = [
                "parts": [
                    ["text": "You are a helpful assistant. Answer questions based on the provided webpage content:\n\n\(context)"]
                ]
            ]
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = try await makeStreamingAPIRequest(
                        endpoint: "/models/\(modelId):streamGenerateContent",
                        payload: payload
                    )
                    
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: handleAPIError(error))
                }
            }
        }
    }
    
    override func generateRawResponse(
        prompt: String,
        model: AIModel?
    ) async throws -> String {
        let modelId = model?.id ?? selectedModel?.id ?? "gemini-2.0-flash-exp"
        
        await applyRateLimit()
        
        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 2048,
                "temperature": 0.7
            ]
        ]
        
        let response = try await makeAPIRequest(
            endpoint: "/models/\(modelId):generateContent",
            payload: payload
        )
        
        guard let candidates = response["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw AIProviderError.providerSpecificError("Invalid response format from Gemini")
        }
        
        return text
    }
    
    override func summarizeConversation(
        _ messages: [ConversationMessage],
        model: AIModel?
    ) async throws -> String {
        let conversationText = messages.map { "\($0.role.description): \($0.content)" }.joined(separator: "\n")
        
        let summaryPrompt = """
        Summarize the following conversation in 2-3 sentences, focusing on the main topics and outcomes:
        
        \(conversationText)
        
        Summary:
        """
        
        return try await generateRawResponse(prompt: summaryPrompt, model: model)
    }
    
    // MARK: - API Communication
    
    private func makeAPIRequest(
        endpoint: String,
        payload: [String: Any]
    ) async throws -> [String: Any] {
        guard let apiKey = apiKey else {
            throw AIProviderError.missingAPIKey(displayName)
        }
        
        // Construct URL with API key as query parameter
        guard var urlComponents = URLComponents(string: baseURL + endpoint) else {
            throw AIProviderError.invalidConfiguration("Invalid API endpoint")
        }
        
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        guard let url = urlComponents.url else {
            throw AIProviderError.invalidConfiguration("Failed to construct URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AIProviderError.invalidConfiguration("Failed to serialize request")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.networkError(URLError(.badServerResponse))
        }
        
        // Handle HTTP errors
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 400:
            throw AIProviderError.invalidConfiguration("Bad request to Gemini API")
        case 401:
            throw AIProviderError.authenticationFailed
        case 429:
            throw AIProviderError.rateLimitExceeded
        default:
            throw AIProviderError.providerSpecificError("HTTP \(httpResponse.statusCode)")
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AIProviderError.providerSpecificError("Invalid JSON response")
            }
            
            // Check for API errors
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIProviderError.providerSpecificError("Gemini API error: \(message)")
            }
            
            return json
        } catch {
            throw AIProviderError.providerSpecificError("Failed to parse response")
        }
    }
    
    private func makeStreamingAPIRequest(
        endpoint: String,
        payload: [String: Any]
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let apiKey = apiKey else {
            throw AIProviderError.missingAPIKey(displayName)
        }
        
        // Construct URL with API key as query parameter
        guard var urlComponents = URLComponents(string: baseURL + endpoint) else {
            throw AIProviderError.invalidConfiguration("Invalid API endpoint")
        }
        
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        guard let url = urlComponents.url else {
            throw AIProviderError.invalidConfiguration("Failed to construct URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        throw AIProviderError.networkError(URLError(.badServerResponse))
                    }
                    
                    for try await line in bytes.lines {
                        // Gemini uses newline-delimited JSON format
                        if !line.isEmpty,
                           let jsonData = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                           let candidates = json["candidates"] as? [[String: Any]],
                           let firstCandidate = candidates.first,
                           let content = firstCandidate["content"] as? [String: Any],
                           let parts = content["parts"] as? [[String: Any]],
                           let firstPart = parts.first,
                           let text = firstPart["text"] as? String {
                            continuation.yield(text)
                        }
                    }
                    
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func buildContents(
        query: String,
        context: String?,
        history: [ConversationMessage]
    ) -> [[String: Any]] {
        var contents: [[String: Any]] = []
        
        // Recent conversation history (last 10 messages, converted to Gemini format)
        let recentHistory = Array(history.suffix(10))
        for message in recentHistory {
            let role = message.role == .user ? "user" : "model"
            contents.append([
                "role": role,
                "parts": [
                    ["text": message.content]
                ]
            ])
        }
        
        // Current query
        contents.append([
            "role": "user",
            "parts": [
                ["text": query]
            ]
        ])
        
        return contents
    }
    
    private func applyRateLimit() async {
        let timeSinceLastRequest = Date().timeIntervalSince(lastRequestTime)
        if timeSinceLastRequest < minimumRequestInterval {
            let delay = minimumRequestInterval - timeSinceLastRequest
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        lastRequestTime = Date()
    }
    
    private func handleAPIError(_ error: Error) -> Error {
        if let urlError = error as? URLError {
            return AIProviderError.networkError(urlError)
        }
        return AIProviderError.providerSpecificError(error.localizedDescription)
    }
    
    // MARK: - Settings
    
    override func getConfigurableSettings() -> [AIProviderSetting] {
        return [
            AIProviderSetting(
                id: "model_selection",
                name: "Model",
                description: "Select the Gemini model to use",
                type: .selection(availableModels.map { $0.name }),
                defaultValue: "Gemini 2.0 Flash",
                currentValue: selectedModel?.name ?? "Gemini 2.0 Flash",
                isRequired: true
            ),
            AIProviderSetting(
                id: "temperature",
                name: "Temperature",
                description: "Controls randomness in responses (0.0-2.0)",
                type: .number,
                defaultValue: 0.7,
                currentValue: 0.7,
                isRequired: false
            ),
            AIProviderSetting(
                id: "top_k",
                name: "Top K",
                description: "Limits token selection to top K candidates",
                type: .number,
                defaultValue: 40,
                currentValue: 40,
                isRequired: false
            )
        ]
    }
}