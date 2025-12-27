#!/usr/bin/env python3
"""
Fine-tune FunctionGemma 270M for CosmoOS using MLX-LM LoRA.

This script:
1. Converts training data to MLX-LM format
2. Downloads FunctionGemma 270M from HuggingFace
3. Runs LoRA fine-tuning
4. Saves the fine-tuned adapter

Target: CosmoOS voice command dispatch with <300ms latency
"""

import json
import subprocess
import sys
from pathlib import Path


# Paths
SCRIPT_DIR = Path(__file__).parent
TRAINING_DATA_DIR = SCRIPT_DIR / "training_data"
MODELS_DIR = SCRIPT_DIR.parent / "Models" / "FunctionGemma"
ADAPTERS_DIR = MODELS_DIR / "adapters"

# Model configuration - FunctionGemma 270M (Dec 2025)
# This is Google's purpose-built function-calling model based on Gemma 3
# Using the pre-converted MLX version (not gated, no auth required)
BASE_MODEL = "lmstudio-community/functiongemma-270m-it-MLX-bf16"  # Pre-converted MLX version

# LoRA configuration optimized for FunctionGemma 270M
# Smaller model = can use more aggressive fine-tuning
LORA_CONFIG = {
    "lora_layers": 8,      # Fewer layers for 270M model
    "lora_rank": 8,        # Keep rank moderate
    "lora_alpha": 16,      # 2x rank for stable training
    "lora_dropout": 0.05,
}

# Training configuration for 270M model
# ~14K examples, batch 4 = ~3500 steps per epoch
TRAIN_CONFIG = {
    "batch_size": 4,
    "iters": 300,          # ~0.1 epochs, enough for fine-tuning pre-trained function model
    "learning_rate": 2e-5, # Slightly higher LR for smaller model
    "warmup_steps": 30,
    "save_every": 100,
    "val_batches": 25,
    "grad_checkpoint": False,  # Not needed for 270M model
}


def prepare_training_data():
    """Prepare training data for FunctionGemma fine-tuning.

    FunctionGemma uses native format with 'developer' and 'model' roles,
    which mlx-lm should handle correctly via the model's chat template.
    We use the original training data files directly.
    """
    print("Preparing training data for FunctionGemma...")

    # Use original files with developer/model roles (FunctionGemma native format)
    train_path = TRAINING_DATA_DIR / "train_original.jsonl"
    valid_path = TRAINING_DATA_DIR / "valid_original.jsonl"

    # Count examples
    train_count = sum(1 for _ in open(train_path))
    valid_count = sum(1 for _ in open(valid_path))

    print(f"  Training examples: {train_count}")
    print(f"  Validation examples: {valid_count}")
    print(f"  Format: FunctionGemma native (developer/user/model roles)")

    # Copy to expected names for mlx-lm
    import shutil
    shutil.copy(train_path, TRAINING_DATA_DIR / "train.jsonl")
    shutil.copy(valid_path, TRAINING_DATA_DIR / "valid.jsonl")

    print(f"  Copied to train.jsonl and valid.jsonl")

    return TRAINING_DATA_DIR / "train.jsonl", TRAINING_DATA_DIR / "valid.jsonl"


def check_mlx_lm():
    """Check if mlx-lm is installed."""
    try:
        result = subprocess.run(
            [sys.executable, "-m", "mlx_lm", "--help"],
            capture_output=True,
            text=True
        )
        return result.returncode == 0
    except Exception:
        return False


def install_mlx_lm():
    """Install mlx-lm if not present."""
    print("Installing mlx-lm...")
    subprocess.run([
        sys.executable, "-m", "pip", "install",
        "mlx-lm", "--upgrade"
    ], check=True)


def download_model():
    """Download the base model for fine-tuning."""
    print(f"Checking/downloading base model: {BASE_MODEL}")

    # MLX-LM will download on first use, but we can pre-download
    try:
        subprocess.run([
            sys.executable, "-m", "mlx_lm.convert",
            "--hf-path", BASE_MODEL,
            "--mlx-path", str(MODELS_DIR / "base"),
            "-q"  # Quantize to 4-bit
        ], check=True)
        print(f"  Model downloaded to {MODELS_DIR / 'base'}")
    except subprocess.CalledProcessError as e:
        print(f"  Note: Model conversion may have issues, continuing anyway...")


def run_finetuning(train_path: Path, valid_path: Path):
    """Run LoRA fine-tuning with MLX-LM."""
    print("\nStarting LoRA fine-tuning...")
    print(f"  Base model: {BASE_MODEL}")
    print(f"  Training data: {train_path}")
    print(f"  Validation data: {valid_path}")
    print(f"  LoRA config: rank={LORA_CONFIG['lora_rank']}, alpha={LORA_CONFIG['lora_alpha']}")
    print(f"  Training: {TRAIN_CONFIG['iters']} iterations, batch_size={TRAIN_CONFIG['batch_size']}")

    # Create adapters directory
    ADAPTERS_DIR.mkdir(parents=True, exist_ok=True)
    adapter_path = ADAPTERS_DIR / "cosmo-v1"

    # Build MLX-LM lora command (updated API for mlx-lm 0.30+)
    cmd = [
        sys.executable, "-m", "mlx_lm", "lora",  # New command structure
        "--model", BASE_MODEL,
        "--train",
        "--data", str(TRAINING_DATA_DIR),
        "--adapter-path", str(adapter_path),
        "--iters", str(TRAIN_CONFIG["iters"]),
        "--batch-size", str(TRAIN_CONFIG["batch_size"]),
        "--learning-rate", str(TRAIN_CONFIG["learning_rate"]),
        "--num-layers", str(LORA_CONFIG["lora_layers"]),  # Renamed param
        "--save-every", str(TRAIN_CONFIG["save_every"]),
        "--val-batches", str(TRAIN_CONFIG["val_batches"]),
        "--fine-tune-type", "lora",
    ]

    if TRAIN_CONFIG.get("grad_checkpoint"):
        cmd.append("--grad-checkpoint")

    print(f"\nRunning: {' '.join(cmd)}\n")

    try:
        # Run with real-time output
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )

        for line in iter(process.stdout.readline, ''):
            print(line, end='')

        process.wait()

        if process.returncode == 0:
            print(f"\n Fine-tuning complete! Adapter saved to: {adapter_path}")
            return adapter_path
        else:
            print(f"\n Fine-tuning failed with return code: {process.returncode}")
            return None

    except Exception as e:
        print(f"\n Fine-tuning error: {e}")
        return None


def test_finetuned_model(adapter_path: Path):
    """Test the fine-tuned model with sample commands."""
    print("\nTesting fine-tuned model...")

    test_commands = [
        "Create idea about marketing automation",
        "What's my level?",
        "Start deep work for 2 hours",
        "Mark as complete",
        "Task call mom at 3pm",
    ]

    for cmd in test_commands:
        print(f"\nInput: {cmd}")
        try:
            result = subprocess.run([
                sys.executable, "-m", "mlx_lm.generate",
                "--model", BASE_MODEL,
                "--adapter-path", str(adapter_path),
                "--prompt", f"User command: {cmd}",
                "--max-tokens", "100",
                "--temp", "0.0"
            ], capture_output=True, text=True, timeout=30)

            if result.returncode == 0:
                print(f"Output: {result.stdout.strip()}")
            else:
                print(f"Error: {result.stderr}")
        except subprocess.TimeoutExpired:
            print("  (timeout)")
        except Exception as e:
            print(f"  Error: {e}")


def create_swift_model_config(adapter_path: Path):
    """Create Swift configuration for loading the fine-tuned model."""
    config_path = MODELS_DIR / "CosmoFunctionGemmaConfig.swift"

    config_content = f'''// CosmoOS/Models/FunctionGemma/CosmoFunctionGemmaConfig.swift
// Auto-generated configuration for fine-tuned FunctionGemma model

import Foundation

/// Configuration for the CosmoOS fine-tuned FunctionGemma model
public struct CosmoFunctionGemmaConfig {{
    /// Base model identifier
    public static let baseModel = "{BASE_MODEL}"

    /// Path to LoRA adapter weights
    public static let adapterPath = "Models/FunctionGemma/adapters/cosmo-v1"

    /// LoRA configuration
    public static let loraRank = {LORA_CONFIG["lora_rank"]}
    public static let loraAlpha = {LORA_CONFIG["lora_alpha"]}
    public static let loraLayers = {LORA_CONFIG["lora_layers"]}

    /// Target latency in milliseconds
    public static let targetLatencyMs = 300

    /// Expected RAM usage in MB
    public static let expectedRamMB = 550

    /// Training metadata
    public static let trainingIterations = {TRAIN_CONFIG["iters"]}
    public static let trainingDate = "{__import__('datetime').datetime.now().isoformat()}"
}}
'''

    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    with open(config_path, 'w') as f:
        f.write(config_content)

    print(f"\nCreated Swift config: {config_path}")


def main():
    print("=" * 60)
    print("CosmoOS FunctionGemma Fine-Tuning")
    print("=" * 60)

    # Step 1: Check MLX-LM
    print("\n[1/5] Checking MLX-LM installation...")
    if not check_mlx_lm():
        install_mlx_lm()
    print("  MLX-LM ready")

    # Step 2: Prepare training data (use original FunctionGemma format)
    print("\n[2/5] Preparing training data...")
    train_path, valid_path = prepare_training_data()

    # Step 3: Download base model (optional, MLX-LM does this automatically)
    print("\n[3/5] Preparing base model...")
    # download_model()  # Uncomment if you want to pre-download
    print("  Model will be downloaded during training")

    # Step 4: Run fine-tuning
    print("\n[4/5] Running LoRA fine-tuning...")
    adapter_path = run_finetuning(train_path, valid_path)

    if adapter_path:
        # Step 5: Test and create config
        print("\n[5/5] Testing and creating configuration...")
        test_finetuned_model(adapter_path)
        create_swift_model_config(adapter_path)

        print("\n" + "=" * 60)
        print("FINE-TUNING COMPLETE")
        print("=" * 60)
        print(f"Adapter saved to: {adapter_path}")
        print(f"To use in Swift, load adapter from: {adapter_path}")
    else:
        print("\nFine-tuning failed. Check the errors above.")
        sys.exit(1)


if __name__ == "__main__":
    main()
