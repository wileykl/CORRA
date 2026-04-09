#!/bin/bash

# Script to verify that resources are properly configured for the CorraCAG app

echo "=========================================="
echo "CorraCAG Resource Verification"
echo "=========================================="
echo ""

PROJECT_DIR="/Users/wiley/Documents/Corra/CorraCAG/CorraCAG"
RESOURCES_DIR="$PROJECT_DIR/CorraCAG/Resources"
ICON_DIR="$PROJECT_DIR/CorraCAG/Assets.xcassets/AppIcon.appiconset"

# Check model file
echo "1. Checking model file..."
MODEL_FILE="$RESOURCES_DIR/Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103.gguf"
if [ -f "$MODEL_FILE" ]; then
    SIZE=$(ls -lh "$MODEL_FILE" | awk '{print $5}')
    echo "   ✓ Model file found: $SIZE"
else
    echo "   ✗ Model file NOT FOUND at: $MODEL_FILE"
fi

# Check knowledge cache
echo ""
echo "2. Checking knowledge cache..."
CACHE_FILE="$RESOURCES_DIR/knowledge_cache.json"
if [ -f "$CACHE_FILE" ]; then
    SIZE=$(ls -lh "$CACHE_FILE" | awk '{print $5}')
    echo "   ✓ Knowledge cache found: $SIZE"
else
    echo "   ✗ Knowledge cache NOT FOUND at: $CACHE_FILE"
fi

# Check app icon
echo ""
echo "3. Checking app icon..."
ICON_FILE="$ICON_DIR/icon_1024x1024.png"
if [ -f "$ICON_FILE" ]; then
    SIZE=$(ls -lh "$ICON_FILE" | awk '{print $5}')
    echo "   ✓ App icon found: $SIZE"
else
    echo "   ✗ App icon NOT FOUND at: $ICON_FILE"
fi

# Check Contents.json for icon
echo ""
echo "4. Checking AppIcon configuration..."
if grep -q "icon_1024x1024.png" "$ICON_DIR/Contents.json" 2>/dev/null; then
    echo "   ✓ AppIcon.appiconset/Contents.json references icon_1024x1024.png"
else
    echo "   ✗ AppIcon.appiconset/Contents.json does NOT reference icon_1024x1024.png"
fi

echo ""
echo "=========================================="
echo "Next Steps:"
echo "=========================================="
echo ""
echo "If all files are found, you still need to:"
echo "1. Open CorraCAG.xcodeproj in Xcode"
echo "2. Select 'CorraCAG' target → 'Build Phases' tab"
echo "3. Expand 'Copy Bundle Resources'"
echo "4. Click '+' and add:"
echo "   - Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103.gguf"
echo "   - knowledge_cache.json"
echo "5. Clean build folder (Shift+Cmd+K)"
echo "6. Build and run on your iPhone"
echo ""
echo "See FIX_ICON_AND_MODEL.md for detailed instructions."
echo ""




