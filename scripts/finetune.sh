#!/bin/bash
# CosmoOS 0.5B Fine-Tuning Script
# Run this after generating training data with generate_training_data.py

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$SCRIPT_DIR/training_data"
OUTPUT_DIR="$PROJECT_ROOT/Models/cosmo-voice-0.5b-v1"

echo "🧠 CosmoOS Voice Model Fine-Tuning"
echo "=================================="
echo ""
echo "Data directory: $DATA_DIR"
echo "Output directory: $OUTPUT_DIR"
echo ""

# Check for training data
if [ ! -f "$DATA_DIR/train.jsonl" ]; then
    echo "❌ Error: Training data not found. Run generate_training_data.py first."
    exit 1
fi

# Count examples
TRAIN_COUNT=$(wc -l < "$DATA_DIR/train.jsonl" | tr -d ' ')
VALID_COUNT=$(wc -l < "$DATA_DIR/valid.jsonl" | tr -d ' ')
echo "📊 Training examples: $TRAIN_COUNT"
echo "📊 Validation examples: $VALID_COUNT"
echo ""

# Check for mlx-lm
if ! python3 -c "import mlx_lm" 2>/dev/null; then
    echo "⚠️  mlx-lm not installed. Installing..."
    pip install mlx-lm
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "🚀 Starting fine-tuning..."
echo ""

# Run fine-tuning
python3 -m mlx_lm.lora \
    --model Qwen/Qwen2.5-0.5B-Instruct \
    --data "$DATA_DIR" \
    --train \
    --batch-size 4 \
    --lora-rank 16 \
    --lora-alpha 32 \
    --learning-rate 1e-4 \
    --epochs 3 \
    --output "$OUTPUT_DIR" \
    --test

echo ""
echo "✅ Fine-tuning complete!"
echo ""
echo "📁 Model saved to: $OUTPUT_DIR"
echo ""
echo "📌 Next steps:"
echo "   1. Test the model with: python3 -m mlx_lm.generate --model $OUTPUT_DIR --prompt 'Create task call mom at 2pm'"
echo "   2. Integrate into CosmoVoiceDaemon.swift"
echo "   3. Run benchmark tests"
