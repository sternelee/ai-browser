import Foundation

/// OpenAI provider implementing the AIProvider protocol
/// Supports GPT models with streaming and function calling
@MainActor
class OpenAIProvider: ExternalAPIProvider {

    // MARK: - AIProvider Implementation

    override var providerId: String { "openai" }
    override var displayName: String { "OpenAI GPT" }

    // MARK: - OpenAI Configuration

    private let baseURL = "https://api.openai.com/v1"
    private let userAgent = "Web-Browser/1.0"

    // MARK: - Rate Limiting

    private var lastRequestTime: Date = Date.distantPast
    private let minimumRequestInterval: TimeInterval = 0.1  // 10 requests per second max

    init() {
        super.init(apiProviderType: .openai)
    }

    // MARK: - Model Management

    override func loadAvailableModels() async {
        availableModels = [
            AIModel(
                id: "gpt-4o",
                name: "GPT-4o",
                description: "Most capable GPT-4 model, optimized for chat and creative tasks",
                contextWindow: 128000,
                costPerToken: nil,
                pricing: ModelPricing(
                    inputPerMTokensUSD: 5.0,  // placeholder; update from OpenAI pricing
                    outputPerMTokensUSD: 15.0,  // placeholder; update from OpenAI pricing
                    cachedInputPerMTokensUSD: 2.5
                ),
                capabilities: [
                    .textGeneration, .conversation, .summarization, .codeGeneration,
                    .functionCalling,
                ],
                provider: providerId,
                isAvailable: true
            ),
            AIModel(
                id: "gpt-4o-mini",
                name: "GPT-4o Mini",
                description: "Faster and more affordable GPT-4 model",
                contextWindow: 128000,
                costPerToken: nil,
                pricing: ModelPricing(
                    inputPerMTokensUSD: 0.5,  // placeholder
                    outputPerMTokensUSD: 1.5,  // placeholder
                    cachedInputPerMTokensUSD: 0.25
                ),
                capabilities: [
                    .textGeneration, .conversation, .summarization, .codeGeneration,
                    .functionCalling,
                ],
                provider: providerId,
                isAvailable: true
            ),
            AIModel(
                id: "gpt-3.5-turbo",
                name: "GPT-3.5 Turbo",
                description: "Fast and cost-effective model for simpler tasks",
                contextWindow: 16385,
                costPerToken: nil,
                pricing: ModelPricing(
                    inputPerMTokensUSD: 0.5,  // placeholder
                    outputPerMTokensUSD: 1.5,  // placeholder
                    cachedInputPerMTokensUSD: nil
                ),
                capabilities: [.textGeneration, .conversation, .summarization, .codeGeneration],
                provider: providerId,
                isAvailable: true
            ),
        ]

        // Set default model
        if selectedModel == nil {
            selectedModel =
                availableModels.first { $0.id == "gpt-4o-mini" } ?? availableModels.first
        }

        NSLog("📋 Loaded \(availableModels.count) OpenAI models")
    }

    // MARK: - Configuration Validation

    override func validateConfiguration() async throws {
        guard let apiKey = apiKey else {
            throw AIProviderError.missingAPIKey(displayName)
        }

        // Test API key with a simple request
        let testPayload: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "user", "content": "Hi"]
            ],
            "max_tokens": 5,
        ]

        do {
            let _ = try await makeAPIRequest(
                endpoint: "/chat/completions",
                payload: testPayload
            )
            NSLog("✅ OpenAI API key validated")
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
        let modelId = model?.id ?? selectedModel?.id ?? "gpt-4o-mini"

        // Apply rate limiting
        await applyRateLimit()

        // Build messages (respect per-provider context sharing preference)
        let effectiveContext = isContextSharingEnabled() ? context : nil
        let messages = buildMessages(
            query: query, context: effectiveContext, history: conversationHistory)

        let payload: [String: Any] = [
            "model": modelId,
            "messages": messages,
            "max_tokens": 2048,
            "temperature": 0.7,
            "top_p": 0.9,
        ]

        do {
            let response = try await makeAPIRequest(
                endpoint: "/chat/completions",
                payload: payload
            )

            guard let choices = response["choices"] as? [[String: Any]],
                let firstChoice = choices.first,
                let message = firstChoice["message"] as? [String: Any],
                let content = message["content"] as? String
            else {
                throw AIProviderError.providerSpecificError("Invalid response format from OpenAI")
            }

            // Extract usage information
            var promptTokens = 0
            var completionTokens = 0
            var tokenCount = 0
            var cost: Double? = nil

            if let usage = response["usage"] as? [String: Any] {
                promptTokens = usage["prompt_tokens"] as? Int ?? 0
                completionTokens = usage["completion_tokens"] as? Int ?? 0
                tokenCount = (usage["total_tokens"] as? Int) ?? (promptTokens + completionTokens)
                cost = estimateCostUSD(
                    forModelId: modelId, promptTokens: promptTokens,
                    completionTokens: completionTokens)
            }

            let responseTime = Date().timeIntervalSince(startTime)
            updateUsageStats(
                tokenCount: tokenCount,
                responseTime: responseTime,
                cost: cost,
                error: false
            )
            // Usage store event
            AIUsageStore.shared.append(
                providerId: providerId,
                modelId: modelId,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                estimatedCostUSD: cost,
                success: true,
                latencyMs: Int(responseTime * 1000),
                contextIncluded: (context != nil)
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
                text: content,
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
        let modelId = model?.id ?? selectedModel?.id ?? "gpt-4o-mini"

        // Apply rate limiting
        await applyRateLimit()

        // Build messages (respect per-provider context sharing preference)
        let effectiveContext = isContextSharingEnabled() ? context : nil
        let messages = buildMessages(
            query: query, context: effectiveContext, history: conversationHistory)

        let payload: [String: Any] = [
            "model": modelId,
            "messages": messages,
            "max_tokens": 2048,
            "temperature": 0.7,
            "top_p": 0.9,
            "stream": true,
        ]

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let startTime = Date()
                    var charCount = 0
                    let stream = try await makeStreamingAPIRequest(
                        endpoint: "/chat/completions",
                        payload: payload
                    )

                    for try await chunk in stream {
                        charCount += chunk.count
                        continuation.yield(chunk)
                    }

                    // Log usage on finish (estimate tokens on streaming)
                    let estTokens = Int((Double(charCount) / 4.0).rounded())
                    let responseTime = Date().timeIntervalSince(startTime)
                    let estCost = estimateCostUSD(
                        forModelId: modelId, promptTokens: 0, completionTokens: estTokens)
                    AIUsageStore.shared.append(
                        providerId: providerId,
                        modelId: modelId,
                        promptTokens: 0,
                        completionTokens: estTokens,
                        estimatedCostUSD: estCost,
                        success: true,
                        latencyMs: Int(responseTime * 1000),
                        contextIncluded: (context != nil)
                    )

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
        let modelId = model?.id ?? selectedModel?.id ?? "gpt-4o-mini"

        await applyRateLimit()

        let payload: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 1024,
            "temperature": 0.7,
        ]

        let response = try await makeAPIRequest(
            endpoint: "/chat/completions",
            payload: payload
        )

        guard let choices = response["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let message = firstChoice["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AIProviderError.providerSpecificError("Invalid response format from OpenAI")
        }

        return content
    }

    override func summarizeConversation(
        _ messages: [ConversationMessage],
        model: AIModel?
    ) async throws -> String {
        let conversationText = messages.map { "\($0.role.description): \($0.content)" }.joined(
            separator: "\n")

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
        // Circuit breaker
        try preflightCircuitBreaker()

        guard let apiKey = apiKey else {
            throw AIProviderError.missingAPIKey(displayName)
        }

        guard let url = URL(string: baseURL + endpoint) else {
            throw AIProviderError.invalidConfiguration("Invalid API endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AIProviderError.invalidConfiguration("Failed to serialize request")
        }

        var lastError: Error?
        var lastStatus: Int?
        var lastResponse: HTTPURLResponse?
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AIProviderError.networkError(URLError(.badServerResponse))
                }
                lastResponse = httpResponse

                switch httpResponse.statusCode {
                case 200...299:
                    // Success
                    recordRequestSuccess()
                    do {
                        guard
                            let json = try JSONSerialization.jsonObject(with: data)
                                as? [String: Any]
                        else {
                            throw AIProviderError.providerSpecificError("Invalid JSON response")
                        }
                        return json
                    } catch {
                        throw AIProviderError.providerSpecificError("Failed to parse response")
                    }
                case 401:
                    // Auth errors shouldn't be retried
                    recordRequestFailure(httpStatus: 401)
                    throw AIProviderError.authenticationFailed
                case 429, 500, 502, 503, 504:
                    lastStatus = httpResponse.statusCode
                    // Retry with backoff
                    if attempt < maxAttempts {
                        let delay = backoffDelayForAttempt(attempt, response: httpResponse)
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    } else {
                        recordRequestFailure(httpStatus: httpResponse.statusCode)
                        throw AIProviderError.providerSpecificError(
                            "HTTP \(httpResponse.statusCode)")
                    }
                default:
                    recordRequestFailure(httpStatus: httpResponse.statusCode)
                    throw AIProviderError.providerSpecificError("HTTP \(httpResponse.statusCode)")
                }
            } catch {
                lastError = error
                // Network level errors: retry unless out of attempts
                if attempt < maxAttempts {
                    let delay = backoffDelayForAttempt(attempt, response: lastResponse)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                } else {
                    recordRequestFailure(httpStatus: lastStatus)
                    throw handleAPIError(error)
                }
            }
        }
        // Should not reach here
        recordRequestFailure(httpStatus: lastStatus)
        throw lastError ?? AIProviderError.providerSpecificError("Unknown error")
    }

    private func makeStreamingAPIRequest(
        endpoint: String,
        payload: [String: Any]
    ) async throws -> AsyncThrowingStream<String, Error> {
        // Circuit breaker
        try preflightCircuitBreaker()

        guard let apiKey = apiKey else {
            throw AIProviderError.missingAPIKey(displayName)
        }

        guard let url = URL(string: baseURL + endpoint) else {
            throw AIProviderError.invalidConfiguration("Invalid API endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                        httpResponse.statusCode == 200
                    else {
                        recordRequestFailure(httpStatus: (response as? HTTPURLResponse)?.statusCode)
                        throw AIProviderError.networkError(URLError(.badServerResponse))
                    }

                    recordRequestSuccess()
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6))

                            if data == "[DONE]" {
                                break
                            }

                            if let jsonData = data.data(using: .utf8),
                                let json = try? JSONSerialization.jsonObject(with: jsonData)
                                    as? [String: Any],
                                let choices = json["choices"] as? [[String: Any]],
                                let firstChoice = choices.first,
                                let delta = firstChoice["delta"] as? [String: Any],
                                let content = delta["content"] as? String
                            {
                                continuation.yield(content)
                            }
                        }
                    }

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: handleAPIError(error))
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func buildMessages(
        query: String,
        context: String?,
        history: [ConversationMessage]
    ) -> [[String: String]] {
        var messages: [[String: String]] = []

        // System message
        var systemContent =
            "You are a helpful assistant. Answer questions based on provided webpage content."
        if let context = context, !context.isEmpty {
            systemContent += "\n\nWebpage content:\n\(context)"
        }
        messages.append(["role": "system", "content": systemContent])

        // Recent conversation history (last 10 messages)
        let recentHistory = Array(history.suffix(10))
        for message in recentHistory {
            let role = message.role == .user ? "user" : "assistant"
            messages.append(["role": role, "content": message.content])
        }

        // Current query
        messages.append(["role": "user", "content": query])

        return messages
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
                description: "Select the GPT model to use",
                type: .selection(availableModels.map { $0.name }),
                defaultValue: "GPT-4o Mini",
                currentValue: selectedModel?.name ?? "GPT-4o Mini",
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
        ]
    }
}
