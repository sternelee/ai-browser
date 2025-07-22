#!/bin/bash

# Model Conversion Script for Web Browser AI
# Converts GGUF Gemma models to MLX format for Apple Silicon optimization
# Usage: ./convert_gemma.sh

set -e

# Configuration
MODEL_NAME="gemma-2-2b-it"
GGUF_SOURCE="bartowski/gemma-2-2b-it-gguf"
MLX_OUTPUT="gemma-2b-mlx-int4"
CACHE_DIR="$HOME/Library/Caches/Web/AI/Models"
BITS=4

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    log "Checking dependencies..."
    
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is required but not installed"
        exit 1
    fi
    
    if ! python3 -c "import mlx_lm" &> /dev/null; then
        error "mlx_lm is required but not installed"
        echo "Install with: pip install mlx-lm"
        exit 1
    fi
    
    log "Dependencies OK"
}

# Create cache directory
setup_directories() {
    log "Setting up directories..."
    mkdir -p "$CACHE_DIR"
    log "Cache directory: $CACHE_DIR"
}

# Check if model already exists
check_existing_model() {
    if [ -d "$CACHE_DIR/$MLX_OUTPUT" ]; then
        warn "MLX model already exists at $CACHE_DIR/$MLX_OUTPUT"
        read -p "Do you want to reconvert? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Using existing model"
            exit 0
        fi
        rm -rf "$CACHE_DIR/$MLX_OUTPUT"
    fi
}

# Convert model
convert_model() {
    log "Starting model conversion..."
    log "Source: $GGUF_SOURCE"
    log "Output: $CACHE_DIR/$MLX_OUTPUT"
    log "Quantization: ${BITS}-bit"
    
    cd "$CACHE_DIR"
    
    python3 -m mlx_lm.convert \
        --hf-path "$GGUF_SOURCE" \
        --mlx-path "$MLX_OUTPUT" \
        --quantize \
        --q-bits $BITS
    
    if [ $? -eq 0 ]; then
        log "✅ Model conversion successful!"
        log "MLX model saved to: $CACHE_DIR/$MLX_OUTPUT"
    else
        error "❌ Model conversion failed"
        exit 1
    fi
}

# Verify conversion
verify_model() {
    log "Verifying converted model..."
    
    if [ ! -f "$CACHE_DIR/$MLX_OUTPUT/config.json" ]; then
        error "config.json not found - conversion may have failed"
        exit 1
    fi
    
    if [ ! -f "$CACHE_DIR/$MLX_OUTPUT/tokenizer.model" ]; then
        warn "tokenizer.model not found - may affect tokenization"
    fi
    
    # Check model size
    MODEL_SIZE=$(du -sh "$CACHE_DIR/$MLX_OUTPUT" | cut -f1)
    log "Model size: $MODEL_SIZE"
    
    # List key files
    log "Model contents:"
    ls -la "$CACHE_DIR/$MLX_OUTPUT" | grep -E '\.(safetensors|json|model)$'
    
    log "✅ Model verification complete"
}

# Update README
create_readme() {
    log "Creating model README..."
    
    cat > "$CACHE_DIR/$MLX_OUTPUT/README.md" << EOF
# Gemma 2B MLX Model

This is a converted MLX model for the Web browser's local AI assistant.

## Model Details
- **Original**: $GGUF_SOURCE
- **Architecture**: Gemma 2B Instruct
- **Quantization**: ${BITS}-bit integer
- **Framework**: MLX (Apple Silicon optimized)
- **Converted**: $(date)

## Usage
This model is automatically loaded by the Web browser when the AI assistant is activated.

## Performance (Estimated)
- **M1 Mac**: ~20-30 tokens/second
- **M3 Max**: ~70-100 tokens/second
- **Memory Usage**: ~2-3GB during inference

## Files
- \`config.json\` - Model configuration
- \`tokenizer.model\` - SentencePiece tokenizer
- \`*.safetensors\` - Model weights (quantized)

## Conversion Command
\`\`\`bash
python3 -m mlx_lm.convert \\
    --hf-path $GGUF_SOURCE \\
    --mlx-path $MLX_OUTPUT \\
    --quantize \\
    --q-bits $BITS
\`\`\`
EOF

    log "README created at $CACHE_DIR/$MLX_OUTPUT/README.md"
}

# Main execution
main() {
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}    Web Browser - Gemma Model Converter    ${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    
    check_dependencies
    setup_directories
    check_existing_model
    convert_model
    verify_model
    create_readme
    
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}    Conversion Complete! 🎉               ${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo
    log "Next steps:"
    log "1. Launch the Web browser"
    log "2. Open AI assistant (⇧⌘A)"
    log "3. The model will be automatically detected and loaded"
    echo
}

# Run main function
main "$@"