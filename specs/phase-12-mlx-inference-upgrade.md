# Phase 12: MLX Swift Real-Inference Upgrade

_Last updated: July 22, 2025_

## Objective
Replace the temporary placeholder/numeric stub responses with **genuine Gemma model text generation** using the WWDC 2025 MLX Swift LLM APIs (`MLX`, `MLXLMCommon`, `MLXLLM`). This brings true on-device privacy-preserving AI capabilities to the Web browser.

## Why Now?
• Apple’s WWDC 2025 shipped MLX 0.27+ with ready-made Swift APIs for loading, quantising, and streaming LLM output.<br>• Our current `GemmaService` still emits hard-coded sentences – this blocks usability testing for the AI sidebar.<br>• Leveraging the official APIs reduces maintenance and unlocks fine-tuning, KV-cache, quantisation, and future foundation-model interoperability.

## Deliverables
1. **Dependency Upgrade**
   – Bump `mlx-swift` package to ≥ 0.27.0 (main, done)  (WWDC 25 tag); include new sub-targets `MLXLMCommon` and `MLXLLM` from `mlx-swift-examples` (done).<br>   – Resolve SwiftPM graph; ensure codesigning scripts updated.
2. **Model Conversion**
   – Convert `gemma-3n-2b-it.Q8_0.gguf` to MLX weights via   
     `mlx_lm.convert --hf-path bartowski/gemma-2-2b-it-gguf --mlx-path gemma-2b-mlx-int4 --quantize --q-bits 4`  
     (run once in CI script, artefact cached to `~/Library/Caches/Web/AI/Models`).
3. **Inference Engine**
   – New helper `MLXGemmaRunner.swift` encapsulating:
     ```swift
     import MLX
     import MLXLMCommon
     import MLXLLM
     ```
     • Lazy `LLMModelContainer` loading (singleton).
     • SentencePiece tokenizer from model bundle (`tokenizer.model`).
     • Async `generate(prompt:, parameters:) -> AsyncThrowingStream<String,Error>` using built-in KV cache.
4. **Service Integration**
   – Replace placeholder logic in `GemmaService.runMLXInference` / `streamMLXInference` with calls to `MLXGemmaRunner`.
   – Remove `SimpleTokenizer.decode()` fallback for MLX pathway; retain for CPU fallback only.
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
│   └── MLXGemmaRunner.swift   # NEW – thin wrapper around MLX LLM APIs
├── Services/
│   └── GemmaService.swift     # Replace placeholder branches
└── Utils/
    └── MLXWrapper.swift       # Minor: expose memory usage, speed stats

specs/
├── phase-12-mlx-inference-upgrade.md  # <-- this file
└── local-ai-integration-spec.md       # Will get delta update
```

## Roll-out Steps
1. **Upgrade packages**: 1 hr
2. **Model conversion script**: 30 min
3. **Code implementation**: 4 hrs
4. **QA pass on M1 & M3**: 2 hrs
5. **Merge & tag v0.12.0-ai**

---
Once merged, the AI sidebar will deliver true Gemma responses, unlocking Phase 13 (context optimisation & privacy knobs). 

## Progress (July 22)
- ✅ SwiftPM dependency now points to `mlx-swift` main branch.
- ✅ Added additional package `mlx-swift-examples` to pull `MLXLMCommon` & `MLXLLM`.
- ✅ Frameworks linked in Web target.
- ✅ `MLXGemmaRunner.swift` scaffold created.
- ✅ `GemmaService` fast-path now calls runner to bypass placeholder.
- 🔄 Build currently fails – MLX API changed (`LanguageModel` / `Tokenizer`).

## Remaining Work
1. **Fix Build**
   – Update type names in `MLXGemmaRunner.swift` to latest API (`LanguageModel`, `Tokenizer`).
   – Re-import modules if needed (`MLXLMCommon`).
2. **Streaming Generation**
   – Add streaming variant so AISidebar shows live typing.
3. **Tokenizer Bridging**
   – Drop SimpleTokenizer when MLX is active; use native tokenizer output.
4. **Model Conversion Script**
   – `scripts/convert_gemma.sh` and README.
5. **Unit & Performance Tests**
6. **Spec & Docs final pass**

When the build is green the placeholder path will be removed entirely and Phase 12 can be marked complete. 