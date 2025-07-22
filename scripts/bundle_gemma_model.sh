#!/bin/bash

# Bundle Gemma 3n Model Script
# Downloads and packages the smallest Gemma 3n model for out-of-box experience

set -e  # Exit on any error

# Configuration
MODEL_NAME="gemma-3n-E2B-it-Q8_0"
MODEL_URL="https://huggingface.co/ggml-org/gemma-3n-E2B-it-GGUF/resolve/main/gemma-3n-E2B-it-Q8_0.gguf"
MODEL_SIZE="4.79GB"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS_DIR="$PROJECT_ROOT/Web/Resources/AI-Models"
MODEL_FILE="$MODELS_DIR/$MODEL_NAME.gguf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Gemma 3n Model Bundling Script${NC}"
echo -e "${BLUE}===================================${NC}"

# Check requirements
echo -e "\n${YELLOW}📋 Checking requirements...${NC}"

# Check if we're in the right directory
if [ ! -f "$PROJECT_ROOT/Web.xcodeproj/project.pbxproj" ]; then
    echo -e "${RED}❌ Error: Not in Web browser project root directory${NC}"
    echo "Please run this script from the Web project root"
    exit 1
fi

# Check available disk space
echo -e "${YELLOW}💾 Checking disk space...${NC}"
AVAILABLE_SPACE=$(df -h "$PROJECT_ROOT" | tail -1 | awk '{print $4}')
echo "Available space: $AVAILABLE_SPACE"

# Create models directory
echo -e "\n${YELLOW}📁 Creating models directory...${NC}"
mkdir -p "$MODELS_DIR"

# Check if model already exists
if [ -f "$MODEL_FILE" ]; then
    echo -e "${GREEN}✅ Model already exists: $MODEL_FILE${NC}"
    
    # Verify file size (approximately)
    MODEL_FILE_SIZE=$(stat -f%z "$MODEL_FILE" 2>/dev/null || stat -c%s "$MODEL_FILE" 2>/dev/null)
    EXPECTED_SIZE=4790000000  # ~4.79GB
    
    if [ "$MODEL_FILE_SIZE" -gt $((EXPECTED_SIZE - 100000000)) ] && [ "$MODEL_FILE_SIZE" -lt $((EXPECTED_SIZE + 100000000)) ]; then
        echo -e "${GREEN}✅ Model file size looks correct${NC}"
        echo -e "${GREEN}🎉 Model is ready for bundling!${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠️  Model file size unexpected, re-downloading...${NC}"
        rm -f "$MODEL_FILE"
    fi
fi

# Download model
echo -e "\n${BLUE}📥 Downloading Gemma 3n 2B model ($MODEL_SIZE)...${NC}"
echo -e "${YELLOW}⏳ This will take several minutes depending on your internet speed${NC}"

# Try different download methods
download_success=false

# Method 1: wget
if command -v wget >/dev/null 2>&1; then
    echo "Using wget to download..."
    if wget --progress=bar:force:noscroll -O "$MODEL_FILE.tmp" "$MODEL_URL"; then
        mv "$MODEL_FILE.tmp" "$MODEL_FILE"
        download_success=true
    fi
fi

# Method 2: curl (fallback)
if [ "$download_success" = false ] && command -v curl >/dev/null 2>&1; then
    echo "Using curl to download..."
    if curl -L --progress-bar -o "$MODEL_FILE.tmp" "$MODEL_URL"; then
        mv "$MODEL_FILE.tmp" "$MODEL_FILE"
        download_success=true
    fi
fi

# Check if download was successful
if [ "$download_success" = false ]; then
    echo -e "${RED}❌ Failed to download model${NC}"
    echo -e "${YELLOW}💡 You can manually download from:${NC}"
    echo "   $MODEL_URL"
    echo -e "${YELLOW}   And place it at: $MODEL_FILE${NC}"
    exit 1
fi

# Verify downloaded file
echo -e "\n${YELLOW}🔍 Verifying downloaded model...${NC}"

# Check file exists and has reasonable size
if [ ! -f "$MODEL_FILE" ]; then
    echo -e "${RED}❌ Model file not found after download${NC}"
    exit 1
fi

MODEL_FILE_SIZE=$(stat -f%z "$MODEL_FILE" 2>/dev/null || stat -c%s "$MODEL_FILE" 2>/dev/null)
if [ "$MODEL_FILE_SIZE" -lt 1000000000 ]; then  # Less than 1GB probably failed
    echo -e "${RED}❌ Downloaded file seems too small: $MODEL_FILE_SIZE bytes${NC}"
    rm -f "$MODEL_FILE"
    exit 1
fi

# Verify it's a GGUF file
if ! head -c 4 "$MODEL_FILE" | grep -q "GGUF"; then
    echo -e "${RED}❌ Downloaded file doesn't appear to be a valid GGUF model${NC}"
    rm -f "$MODEL_FILE"
    exit 1
fi

echo -e "${GREEN}✅ Model downloaded and verified successfully${NC}"
echo "File size: $(ls -lh "$MODEL_FILE" | awk '{print $5}')"

# Add to Xcode project
echo -e "\n${YELLOW}🔨 Configuring Xcode project...${NC}"

# Create a simple script to remind about Xcode configuration
cat > "$MODELS_DIR/README_XCODE_SETUP.md" << EOF
# Xcode Setup Required

After running the bundle script, you need to:

1. **Add the AI-Models folder to Xcode:**
   - Right-click on Web/Resources in Xcode
   - Choose "Add Files to Web..."  
   - Select the AI-Models folder
   - ✅ Check "Copy items if needed"
   - ✅ Check "Create folder references" (not groups)
   - ✅ Add to target: Web

2. **Verify bundle resources:**
   - Build Settings → Build Phases → Copy Bundle Resources  
   - Ensure AI-Models folder is listed
   - If not, drag it there manually

3. **Test the integration:**
   - Build and run the app
   - Check that BundledModelService finds the model
   - AI should work out-of-the-box!

Model file: $(basename "$MODEL_FILE")
Size: $(ls -lh "$MODEL_FILE" | awk '{print $5}')
EOF

echo -e "${GREEN}✅ Setup instructions created${NC}"

# Final summary
echo -e "\n${GREEN}🎉 MODEL BUNDLING COMPLETE!${NC}"
echo -e "${GREEN}=========================${NC}"
echo -e "${GREEN}✅ Model: $MODEL_NAME${NC}"
echo -e "${GREEN}✅ Size: $(ls -lh "$MODEL_FILE" | awk '{print $5}')${NC}"
echo -e "${GREEN}✅ Location: $MODEL_FILE${NC}"

echo -e "\n${YELLOW}📋 NEXT STEPS:${NC}"
echo "1. Add AI-Models folder to Xcode project (see instructions in AI-Models/README_XCODE_SETUP.md)"
echo "2. Build the Web browser app"
echo "3. AI will work out-of-the-box for users! 🚀"

echo -e "\n${BLUE}💡 App Bundle Size Impact:${NC}"
echo "Your .app bundle will increase by ~$MODEL_SIZE"
echo "Users get instant AI without any downloads or setup!"

echo -e "\n${GREEN}✨ Done! The Web browser now has embedded AI capabilities.${NC}"