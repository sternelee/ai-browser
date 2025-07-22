# Phase 12: LLM.swift Integration & Real AI Inference

_Last updated: July 22, 2025_

## Objective
Replace the temporary placeholder/numeric stub responses with **genuine Gemma model text generation** using the LLM.swift package from eastriverlee. This brings true on-device privacy-preserving AI capabilities to the Web browser with a simplified, production-ready Swift API.

## Why LLM.swift?
• **Simplified Integration**: LLM.swift provides a clean, readable Swift API that abstracts complex MLX/llama.cpp operations.<br>• **Production Ready**: Battle-tested library with comprehensive examples and documentation.<br>• **Structured Output**: Built-in @Generatable macro for type-safe AI responses (100% reliable JSON parsing).<br>• **Cross-Platform**: Supports both bundled models and HuggingFace downloads with automatic fallbacks.<br>• **Performance**: Optimized for Apple Silicon while maintaining compatibility with Intel Macs.

## Deliverables
1. **Package Integration**
   – Add LLM.swift package dependency: `https://github.com/eastriverlee/LLM.swift`<br>   – Configure Swift Package Manager and resolve dependencies.
2. **Model Setup**
   – Use existing GGUF models (already downloaded): `gemma-3n-2b-it.Q8_0.gguf`<br>   – Bundle model in app or configure HuggingFace download via `HuggingFaceModel("bartowski/gemma-2-2b-it-GGUF", .Q4_K_M)`
3. **LLM Integration**
   – Create `LLMGemmaRunner.swift` wrapper class:
     ```swift
     import LLM
     
     class GemmaBot: LLM {
         convenience init() {
             let url = Bundle.main.url(forResource: "gemma-3n-2b-it", withExtension: "gguf")!
             let systemPrompt = "You are a helpful AI assistant integrated into a web browser."
             self.init(from: url, template: .gemma)!
         }
     }
     ```
4. **Service Integration**
   – Replace placeholder logic in `GemmaService` with LLM.swift calls
   – Implement streaming responses using `bot.respond(to: input)` with `update` callback
   – Add structured output support with `@Generatable` for specific use cases
5. **UI/UX**
   – Streaming bubbles already supported; ensure partial chunks render as they arrive.
   – Display real tokens-per-second metric from `mlxWrapper.inferenceSpeed`.
6. **Testing**
   – Unit: Verify response is non-empty and not equal to placeholder string.
   – Performance: M1 baseline ≥ 20 tok/s, M3 Max ≥ 70 tok/s.
   – Memory: < 4 GB during inference on 16 GB M1.
7. **Documentation**
   – Update `local-ai-integration-spec.md` context window & hardware tables (<32 k tokens preserved).
   – Add developer guide `docs/MLX-Setup.md`.

## File-Tree Impact
```
Web/AI/
├── Runners/
│   └── LLMGemmaRunner.swift   # NEW – LLM.swift wrapper class
├── Services/
│   └── GemmaService.swift     # Replace placeholder with LLM.swift calls
└── Utils/
    └── (MLXWrapper.swift removed – replaced by LLM.swift)

specs/
├── phase-12-mlx-inference-upgrade.md  # <-- this file (updated for LLM.swift)
└── local-ai-integration-spec.md       # Will get architecture update
```

## Roll-out Steps
1. **Add LLM.swift package**: 30 min
2. **Create LLMGemmaRunner wrapper**: 2 hrs
3. **Update GemmaService integration**: 2 hrs
4. **Test streaming responses**: 1 hr
5. **QA pass on M1 & M3**: 2 hrs
6. **Merge & tag v0.12.0-ai**

---
Once merged, the AI sidebar will deliver true Gemma responses, unlocking Phase 13 (context optimisation & privacy knobs). 

## Progress (July 22)
- ✅ **AI Tab Working**: Successfully implemented AI chat interface with real responses.
- ✅ **LLM.swift Decision**: Transitioned from MLX direct integration to LLM.swift package for simplified development.
- ✅ **Package Research**: Evaluated LLM.swift features including @Generatable macro for structured output.
- ⏳ **Package Integration**: Ready to add LLM.swift dependency to replace current MLX implementation.
- ⏳ **Runner Creation**: Need to create LLMGemmaRunner.swift wrapper class.
- ⏳ **Service Update**: Update GemmaService to use LLM.swift instead of direct MLX calls.

## LLM.swift Integration Benefits
1. **🎯 Simplified API**
   – Single `LLM` class with clean Swift interface
   – Built-in conversation history and state management
   – Automatic template handling (ChatML, Gemma, etc.)
2. **🚀 Advanced Features**
   – `@Generatable` macro for 100% reliable structured output
   – Streaming responses with `update` callback
   – HuggingFace model downloading with progress tracking
   – Automatic hardware detection and optimization
3. **🛡️ Production Ready**
   – Battle-tested with comprehensive examples
   – Cross-platform support (Apple Silicon + Intel)
   – Proper error handling and fallbacks
   – Memory-efficient model loading

## Next Steps
1. **Package Addition**: Add LLM.swift to Xcode project via SPM
2. **Runner Implementation**: Create `LLMGemmaRunner.swift` wrapper class
3. **Service Integration**: Update `GemmaService` to use LLM.swift instead of MLX
4. **Streaming Setup**: Implement real-time response streaming in UI
5. **Testing**: Verify functionality across different Mac configurations

**Status**: 🔄 **IN PROGRESS** – Transitioning to LLM.swift for simplified, production-ready AI integration. 