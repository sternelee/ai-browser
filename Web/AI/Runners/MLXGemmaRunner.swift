import Foundation
import MLX
import MLXLMCommon
import MLXLLM

/// Thin wrapper that loads a Gemma MLX model once and exposes a simple async text‐generation call.
/// We intentionally keep the API minimal – advanced sampling parameters can be added later.
@globalActor
struct GemmaActor {
    actor Shared {}
    static let shared = Shared()
}

@GemmaActor
final class MLXGemmaRunner {
    static let shared = MLXGemmaRunner()
    private var container: ModelContainer?
    private var isLoading = false
    private var loadContinuation: [CheckedContinuation<Void, Error>] = []

    private init() {}

    /// Ensures model and tokenizer are loaded (lazy).
    private func ensureLoaded(modelPath: URL) async throws {
        if container != nil { return }
        if isLoading {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                loadContinuation.append(continuation)
            }
            return
        }
        isLoading = true
        defer { isLoading = false }

        let config = ModelConfiguration(id: modelPath.path) // local path supported
        container = try await LLMModelFactory.shared.loadContainer(configuration: config)

        for cont in loadContinuation { cont.resume() }
        loadContinuation.removeAll()
    }

    /// Generate a full response for the given prompt.
    func generate(prompt: String, maxTokens: Int = 256, temperature: Float = 0.7, modelPath: URL) async throws -> String {
        try await ensureLoaded(modelPath: modelPath)
        guard let container else { throw NSError(domain: "MLXGemmaRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]) }
        
        let generateParameters = GenerateParameters(temperature: temperature, maxTokens: maxTokens)
        var output = ""
        
        try await container.perform { context in
            let userInput = UserInput(prompt: prompt)
            let prepared = try await context.processor.prepare(input: userInput)
            let result = try MLXLMCommon.generate(
                input: prepared,
                parameters: generateParameters,
                context: context
            ) { tokens in
                let text = context.tokenizer.decode(tokens: tokens)
                output.append(text)
                return .more
            }
        }
        return output
    }

    /// Generate a streaming response for the given prompt.
    func generateStream(prompt: String, maxTokens: Int = 256, temperature: Float = 0.7, modelPath: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await ensureLoaded(modelPath: modelPath)
                    guard let container else {
                        continuation.finish(throwing: NSError(domain: "MLXGemmaRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]))
                        return
                    }
                    
                    let generateParameters = GenerateParameters(temperature: temperature, maxTokens: maxTokens)
                    
                    try await container.perform { context in
                        let userInput = UserInput(prompt: prompt)
                        let prepared = try await context.processor.prepare(input: userInput)
                        let result = try MLXLMCommon.generate(
                            input: prepared,
                            parameters: generateParameters,
                            context: context
                        ) { tokens in
                            let text = context.tokenizer.decode(tokens: tokens)
                            continuation.yield(text)
                            return .more
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
} 