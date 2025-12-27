#!/bin/bash
# Regenerate Xcode project from project.yml
# Run this after adding/removing/moving files

cd "$(dirname "$0")"
xcodegen generate
echo "✅ Project regenerated from project.yml"
