#!/bin/bash

# Script to check if resources are included in the Xcode project bundle

echo "=========================================="
echo "Checking Bundle Resources Configuration"
echo "=========================================="
echo ""

PROJECT_FILE="/Users/wiley/Documents/Corra/CorraCAG/CorraCAG/CorraCAG.xcodeproj/project.pbxproj"

# Check if model file is referenced in project
if grep -q "Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103.gguf" "$PROJECT_FILE" 2>/dev/null; then
    echo "✓ Model file is referenced in project.pbxproj"
else
    echo "✗ Model file is NOT referenced in project.pbxproj"
fi

# Check if knowledge cache is referenced in project
if grep -q "knowledge_cache.json" "$PROJECT_FILE" 2>/dev/null; then
    echo "✓ Knowledge cache is referenced in project.pbxproj"
else
    echo "✗ Knowledge cache is NOT referenced in project.pbxproj"
fi

# Check PBXResourcesBuildPhase section
echo ""
echo "Checking PBXResourcesBuildPhase section..."
RESOURCES_SECTION=$(grep -A 10 "PBXResourcesBuildPhase" "$PROJECT_FILE" | grep -A 5 "files = (" | head -10)

if echo "$RESOURCES_SECTION" | grep -q "Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103.gguf\|knowledge_cache.json"; then
    echo "✓ Resources found in PBXResourcesBuildPhase"
else
    echo "✗ Resources NOT found in PBXResourcesBuildPhase"
    echo ""
    echo "Current Resources section:"
    echo "$RESOURCES_SECTION" | head -5
fi

echo ""
echo "=========================================="
echo "Conclusion:"
echo "=========================================="
echo ""
if grep -q "Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103.gguf" "$PROJECT_FILE" && grep -q "knowledge_cache.json" "$PROJECT_FILE"; then
    echo "✓ Resources appear to be configured in the project"
    echo "  However, you should verify in Xcode:"
    echo "  1. Open CorraCAG.xcodeproj"
    echo "  2. Select 'CorraCAG' target → 'Build Phases'"
    echo "  3. Check 'Copy Bundle Resources' section"
    echo "  4. Verify both files are listed and checked"
else
    echo "✗ Resources are NOT configured in the project"
    echo ""
    echo "ACTION REQUIRED:"
    echo "1. Open CorraCAG.xcodeproj in Xcode"
    echo "2. Select 'CorraCAG' target → 'Build Phases' tab"
    echo "3. Expand 'Copy Bundle Resources'"
    echo "4. Click '+' and add:"
    echo "   - CorraCAG/Resources/Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103.gguf"
    echo "   - CorraCAG/Resources/knowledge_cache.json"
    echo "5. Clean build (Shift+Cmd+K) and rebuild"
fi
echo ""




