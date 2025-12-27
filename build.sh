#!/bin/bash
# Build script for CosmoOS

set -e

echo "🚀 Building CosmoOS - The World's First Cognition OS"
echo ""

cd "$(dirname "$0")"

# Check Swift version
echo "📋 Checking Swift version..."
swift --version

echo ""
echo "📦 Resolving dependencies..."
swift package resolve

echo ""
echo "🔨 Building..."
swift build --configuration release

echo ""
echo "✅ Build complete!"
echo ""
echo "To run: swift run CosmoOS"
echo "Or open in Xcode: open Package.swift"
