# MLX Setup Guide - Web Browser AI

This guide explains how to set up and use the MLX-powered local AI assistant in the Web browser.

## Overview

The Web browser includes a revolutionary local AI assistant powered by Apple's MLX framework, providing:

- **Complete Privacy**: All AI processing happens locally on your Mac
- **Apple Silicon Optimization**: Leverages unified memory architecture for fast inference
- **Zero External APIs**: No data leaves your device, ever
- **Real-time Streaming**: Live typing responses as AI generates text
- **Context Awareness**: Understands your browsing context and tab content

## Requirements

### Hardware Requirements
- **Apple Silicon Mac** (M1, M2, M3, or later)
- **8GB+ RAM** recommended (16GB+ for optimal performance)
- **5GB+ free storage** for AI model

### Software Requirements
- **macOS 14.0+** (Sonoma or later)
- **Python 3.8+** (for model conversion only)
- **mlx-lm** package (for model conversion only)

## Quick Setup

### 1. Download the Browser
The Web browser app bundle is only ~50MB - the AI model downloads separately on first use.

### 2. First Launch
1. Launch Web.app
2. The browser automatically detects if the AI model exists
3. If no model is found, you'll see a download prompt when accessing AI features

### 3. AI Model Download
When you first activate the AI assistant (⇧⌘A):
1. Download dialog appears showing model information
2. Click "Download Model" to start the 4.79GB download
3. Progress is shown in real-time
4. Download happens in background while you continue browsing

### 4. Using the AI Assistant
Once the model is downloaded:
- **Activate**: Press ⇧⌘A to open AI sidebar
- **Chat**: Type questions and get instant responses
- **Context**: AI automatically understands your current tab content
- **Streaming**: Watch responses appear in real-time as AI generates text

## Manual Model Setup

If you prefer to set up the model manually or encounter issues:

### 1. Install Dependencies
```bash
# Install MLX LM tools
pip install mlx-lm

# Verify installation
python3 -c "import mlx_lm; print('MLX LM ready')"
```

### 2. Run Conversion Script
```bash
cd /path/to/Web/scripts
./convert_gemma.sh
```

The script will:
- Download Gemma 2B GGUF model from Hugging Face
- Convert to MLX format with 4-bit quantization
- Save to `~/Library/Caches/Web/AI/Models/`
- Verify the conversion completed successfully

### 3. Manual Conversion (Advanced)
If you want to customize the conversion:

```bash
# Create cache directory
mkdir -p ~/Library/Caches/Web/AI/Models
cd ~/Library/Caches/Web/AI/Models

# Convert with custom settings
python3 -m mlx_lm.convert \
    --hf-path bartowski/gemma-2-2b-it-gguf \
    --mlx-path gemma-2b-mlx-int4 \
    --quantize \
    --q-bits 4
```

## Model Information

### Gemma 2B Instruct (MLX Optimized)
- **Architecture**: Google Gemma 2B parameters
- **Quantization**: 4-bit integer for efficiency
- **Context Window**: 8K tokens (~32,000 characters)
- **Model Size**: ~2.4GB on disk (4-bit quantized)
- **Memory Usage**: ~3-4GB during inference

### Performance Benchmarks
| Hardware | Tokens/Second | Memory Usage |
|----------|---------------|--------------|
| M1 Mac (8GB) | 20-30 tok/s | 3-4GB |
| M2 Mac (16GB) | 35-45 tok/s | 3-4GB |
| M3 Max (64GB) | 70-100 tok/s | 3-4GB |

## Architecture Details

### MLX Integration
- **Framework**: Apple MLX Swift bindings
- **Model Loading**: `LLMModelFactory` with lazy initialization
- **Tokenization**: Native SentencePiece tokenizer
- **Generation**: Streaming inference with KV cache
- **Memory**: Unified memory optimization

### File Structure
```
~/Library/Caches/Web/AI/Models/
└── gemma-2b-mlx-int4/
    ├── config.json          # Model configuration
    ├── tokenizer.model       # SentencePiece tokenizer
    ├── weights.safetensors   # Model weights (quantized)
    └── README.md            # Model information
```

### Code Architecture
```
Web/AI/
├── Runners/
│   └── MLXGemmaRunner.swift    # MLX model wrapper
├── Services/
│   └── GemmaService.swift      # Main AI service
└── Utils/
    └── MLXWrapper.swift        # MLX framework bridge
```

## Troubleshooting

### Model Download Issues
**Problem**: Download fails or is interrupted
**Solution**:
1. Check internet connection
2. Ensure sufficient disk space (6GB+ free)
3. Restart download from AI settings

**Problem**: "Model not found" after download
**Solution**:
1. Check `~/Library/Caches/Web/AI/Models/` exists
2. Verify `gemma-2b-mlx-int4/` folder contains files
3. Run conversion script to re-download

### Performance Issues
**Problem**: Slow AI responses
**Solutions**:
1. Close other memory-intensive apps
2. Ensure you're on Apple Silicon (Intel Macs use CPU fallback)
3. Check Activity Monitor for memory pressure

**Problem**: High memory usage
**Solutions**:
1. Quit unused browser tabs
2. Use tab hibernation feature
3. Restart browser to clear memory leaks

### Conversion Errors
**Problem**: `mlx_lm` import errors
**Solution**:
```bash
# Update pip and reinstall
pip install --upgrade pip
pip install --upgrade mlx-lm
```

**Problem**: Permission denied during conversion
**Solution**:
```bash
# Create cache directory with correct permissions
mkdir -p ~/Library/Caches/Web/AI/Models
chmod 755 ~/Library/Caches/Web/AI/Models
```

## Privacy & Security

### Local Processing
- **Zero Network Calls**: All AI processing happens locally
- **No Telemetry**: No usage data sent to external servers  
- **Encrypted Storage**: Conversation history encrypted with AES-256
- **Isolated Processing**: AI context isolated per browser session

### Data Handling
- **Tab Content**: Analyzed locally only when explicitly requested
- **Conversations**: Stored locally with user-controlled retention
- **Model Weights**: Cached locally, never transmitted
- **Context Windows**: Automatically cleaned after sessions

## Advanced Configuration

### Model Variants
For different performance/quality tradeoffs, you can convert other quantizations:

```bash
# Higher quality, larger size (8-bit)
python3 -m mlx_lm.convert \
    --hf-path bartowski/gemma-2-2b-it-gguf \
    --mlx-path gemma-2b-mlx-int8 \
    --quantize \
    --q-bits 8

# Maximum quality, largest size (16-bit)  
python3 -m mlx_lm.convert \
    --hf-path bartowski/gemma-2-2b-it-gguf \
    --mlx-path gemma-2b-mlx-fp16 \
    --quantize \
    --q-bits 16
```

Then update the model path in AI settings to use your preferred variant.

### Custom Models
The MLXGemmaRunner supports any MLX-compatible language model. To use a different model:

1. Convert your model to MLX format
2. Place in `~/Library/Caches/Web/AI/Models/`
3. Update the model path in browser settings

## Support

For technical support or feature requests:
- **GitHub Issues**: [Web Browser Issues](https://github.com/your-repo/web-browser)
- **Documentation**: Check `specs/local-ai-integration-spec.md`
- **Logs**: Check Console.app for Web browser logs

---

**Last Updated**: July 22, 2025  
**MLX Version**: 0.27+  
**Browser Version**: v0.12.0-ai