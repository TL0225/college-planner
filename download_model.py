#!/usr/bin/env python3
"""
Download Llama 3.2 3B (4-bit quantized) model for MLX Swift
"""

from huggingface_hub import snapshot_download
import os

# Set download directory
local_dir = os.path.expanduser("~/Desktop/College/Models/llama-3.2-3b-4bit")

print(f"Downloading Llama 3.2 3B (4-bit) to: {local_dir}")
print("This will download ~2GB of model files...")
print()

try:
    snapshot_download(
        repo_id="mlx-community/Llama-3.2-3B-Instruct-4bit",
        local_dir=local_dir,
        local_dir_use_symlinks=False,
        resume_download=True
    )
    print("\n✅ Model downloaded successfully!")
    print(f"📁 Location: {local_dir}")
    print("\nFiles downloaded:")
    for file in os.listdir(local_dir):
        file_path = os.path.join(local_dir, file)
        if os.path.isfile(file_path):
            size_mb = os.path.getsize(file_path) / (1024 * 1024)
            print(f"  - {file} ({size_mb:.1f} MB)")
    
except Exception as e:
    print(f"\n❌ Error downloading model: {e}")
    print("\nTroubleshooting:")
    print("1. Check internet connection")
    print("2. Try again (script supports resume)")
    print("3. Manual download: https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit")
