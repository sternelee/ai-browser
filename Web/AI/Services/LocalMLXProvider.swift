import Foundation

/// Local MLX provider implementing the AIProvider protocol
/// Wraps existing GemmaService to provide unified interface
@MainActor
class LocalMLXProvider: AIProvider {
    
    // MARK: - AIProvider Implementation
    
    let providerId = "local_mlx"
    let displayName = "Local MLX (Private)"
    let providerType = AIProviderType.local
    
    @Published var isInitialized: Bool = false
    
    var availableModels: [AIModel] = [
        AIModel(
            id: "gemma3_2B_4bit",
            name: "Gemma 3 2B (4-bit)",
            description: "Local privacy-focused model optimized for Apple Silicon with 4-bit quantization",
            contextWindow: 8192,
            costPerToken: nil,
            capabilities: [.textGeneration, .conversation, .summarization],
            provider: "local_mlx",
            isAvailable: true
        )
    ]
    
    var selectedModel: AIModel? {
        didSet {
            if let model = selectedModel {
                UserDefaults.standard.set(model.id, forKey: "localMLXSelectedModel")
            }
        }
    }
    
    // MARK: - Private Properties
    
    private let gemmaService: GemmaService
    private let aiConfiguration: AIConfiguration
    private let mlxWrapper: MLXWrapper
    private let mlxModelService: MLXModelService
    private let privacyManager: PrivacyManager
    
    private var usageStats = AIUsageStatistics(
        requestCount: 0,
        tokenCount: 0,
        averageResponseTime: 0,
        errorCount: 0,
        lastUsed: nil,
        estimatedCost: nil
    )
    
    // MARK: - Initialization
    
    init() {
        // Initialize dependencies (reuse existing services)
        self.mlxWrapper = MLXWrapper()
        self.privacyManager = PrivacyManager()
        self.mlxModelService = MLXModelService()
        
        // Get optimal configuration for current hardware
        self.aiConfiguration = HardwareDetector.getOptimalAIConfiguration()
        
        // Initialize Gemma service
        self.gemmaService = GemmaService(
            configuration: aiConfiguration,
            mlxWrapper: mlxWrapper,
            privacyManager: privacyManager,
            mlxModelService: mlxModelService
        )
        
        // Set default selected model
        if let savedModelId = UserDefaults.standard.string(forKey: "localMLXSelectedModel"),
           let model = availableModels.first(where: { $0.id == savedModelId }) {
            selectedModel = model
        } else {
            selectedModel = availableModels.first
        }
        
        NSLog("🤖 Local MLX Provider initialized with \(aiConfiguration.framework) framework")
    }
    
    // MARK: - Lifecycle Methods
    
    func initialize() async throws {
        do {
            // Validate hardware requirements
            try validateHardware()
            
            // Initialize underlying services
            try await mlxWrapper.initialize()
            try await privacyManager.initialize()
            try await gemmaService.initialize()
            
            isInitialized = true
            NSLog("✅ Local MLX Provider initialization completed")
            
        } catch {
            isInitialized = false
            throw AIProviderError.invalidConfiguration("MLX initialization failed: \(error.localizedDescription)")
        }
    }
    
    func isReady() async -> Bool {
        guard isInitialized else { return false }
        return await mlxModelService.isAIReady()
    }
    
    func cleanup() async {
        isInitialized = false
        // MLX resources are managed by shared services, don't clean up here
        NSLog("🧹 Local MLX Provider cleaned up")
    }
    
    // MARK: - Core AI Methods
    
    func generateResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        model: AIModel?
    ) async throws -> AIResponse {
        let startTime = Date()
        
        do {
            let response = try await gemmaService.generateResponse(
                query: query,
                context: context,
                conversationHistory: conversationHistory
            )
            
            let responseTime = Date().timeIntervalSince(startTime)
            let tokenCount = Int(Double(response.text.count) / 3.5) // Rough estimation
            
            updateUsageStats(
                tokenCount: tokenCount,
                responseTime: responseTime,
                error: false
            )
            
            return response
            
        } catch {
            let responseTime = Date().timeIntervalSince(startTime)
            updateUsageStats(tokenCount: 0, responseTime: responseTime, error: true)
            throw error
        }
    }
    
    func generateStreamingResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        model: AIModel?
    ) async throws -> AsyncThrowingStream<String, Error> {
        return try await gemmaService.generateStreamingResponse(
            query: query,
            context: context,
            conversationHistory: conversationHistory
        )
    }
    
    func generateRawResponse(
        prompt: String,
        model: AIModel?
    ) async throws -> String {
        let startTime = Date()
        
        do {
            let response = try await gemmaService.generateRawResponse(prompt: prompt)
            
            let responseTime = Date().timeIntervalSince(startTime)
            let tokenCount = Int(Double(response.count) / 3.5) // Rough estimation
            
            updateUsageStats(
                tokenCount: tokenCount,
                responseTime: responseTime,
                error: false
            )
            
            return response
            
        } catch {
            let responseTime = Date().timeIntervalSince(startTime)
            updateUsageStats(tokenCount: 0, responseTime: responseTime, error: true)
            throw error
        }
    }
    
    func summarizeConversation(
        _ messages: [ConversationMessage],
        model: AIModel?
    ) async throws -> String {
        return try await gemmaService.summarizeConversation(messages)
    }
    
    // MARK: - Configuration Methods
    
    func validateConfiguration() async throws {
        // Validate hardware compatibility
        try validateHardware()
        
        // Check if model is available
        guard await mlxModelService.isAIReady() else {
            throw AIProviderError.modelNotAvailable("Gemma model not downloaded or corrupted")
        }
    }
    
    func getConfigurableSettings() -> [AIProviderSetting] {
        return [
            AIProviderSetting(
                id: "model_selection",
                name: "Model",
                description: "Select the Gemma model variant to use",
                type: .selection(availableModels.map { $0.name }),
                defaultValue: availableModels.first?.name ?? "",
                currentValue: selectedModel?.name ?? "",
                isRequired: true
            ),
            AIProviderSetting(
                id: "privacy_mode",
                name: "Enhanced Privacy",
                description: "Enable additional privacy protections",
                type: .boolean,
                defaultValue: true,
                currentValue: privacyManager.encryptionEnabled,
                isRequired: false
            )
        ]
    }
    
    func updateSetting(_ setting: AIProviderSetting, value: Any) throws {
        switch setting.id {
        case "model_selection":
            guard let modelName = value as? String,
                  let model = availableModels.first(where: { $0.name == modelName }) else {
                throw AIProviderError.invalidConfiguration("Invalid model selection")
            }
            selectedModel = model
            
        case "privacy_mode":
            guard let enabled = value as? Bool else {
                throw AIProviderError.invalidConfiguration("Privacy mode must be boolean")
            }
            privacyManager.encryptionEnabled = enabled
            
        default:
            throw AIProviderError.unsupportedOperation("Unknown setting: \(setting.id)")
        }
    }
    
    // MARK: - Conversation Management
    
    func resetConversation() async {
        await gemmaService.resetConversation()
        NSLog("🔄 Local MLX conversation state reset")
    }
    
    func getUsageStatistics() -> AIUsageStatistics {
        return usageStats
    }
    
    // MARK: - Private Methods
    
    private func validateHardware() throws {
        switch aiConfiguration.framework {
        case .mlx:
            guard HardwareDetector.isAppleSilicon else {
                throw AIProviderError.invalidConfiguration("MLX requires Apple Silicon")
            }
        case .llamaCpp:
            // Intel Macs supported with llama.cpp
            break
        }
        
        guard HardwareDetector.totalMemoryGB >= 8 else {
            throw AIProviderError.invalidConfiguration("Minimum 8GB RAM required")
        }
    }
    
    private func updateUsageStats(
        tokenCount: Int,
        responseTime: TimeInterval,
        error: Bool = false
    ) {
        usageStats = AIUsageStatistics(
            requestCount: usageStats.requestCount + 1,
            tokenCount: usageStats.tokenCount + tokenCount,
            averageResponseTime: (usageStats.averageResponseTime + responseTime) / 2,
            errorCount: usageStats.errorCount + (error ? 1 : 0),
            lastUsed: Date(),
            estimatedCost: nil // Local models have no cost
        )
    }
}

// MARK: - Hardware Requirements Extension

extension HardwareDetector {
    /// Check if current hardware meets MLX requirements
    static var isMLXCompatible: Bool {
        return isAppleSilicon && totalMemoryGB >= 8
    }
    
    /// Get recommended configuration based on hardware
    static func getRecommendedLocalConfig() -> (model: String, quantization: String) {
        if totalMemoryGB >= 16 {
            return ("gemma3_2B_4bit", "4-bit")
        } else {
            return ("gemma3_2B_4bit", "4-bit") // Conservative for 8GB systems
        }
    }
}