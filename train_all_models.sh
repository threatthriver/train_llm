#!/bin/bash

# Script to train multiple models sequentially, starting with 7B
# This script is designed to maximize the 30-day TPU allocation
# and upload models directly to Hugging Face to save storage space

echo "========================================================"
echo "Setting up environment for sequential model training"
echo "========================================================"

# Install dependencies
pip install -r requirements.txt

# Install compatible version of optax for Python 3.8
pip install 'optax<0.1.7'

# Make the launcher script executable
chmod +x run_all.py

# Set environment variables for TPU
export TPU_NAME=${TPU_NAME:-"v4-32"}
export TPU_ZONE=${TPU_ZONE:-"us-central1-a"}

# Set Hugging Face token
export HF_TOKEN="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"
echo "Using Hugging Face token for direct model uploading"
huggingface-cli login --token $HF_TOKEN

# Create temporary output directories
mkdir -p ./tmp/7b
mkdir -p ./tmp/13b
mkdir -p ./tmp/70b
mkdir -p ./tmp/175b

# Function to check if training was successful
check_training_success() {
  local log_file=$1
  if grep -q "Training completed successfully" "$log_file"; then
    return 0  # Success
  else
    return 1  # Failure
  fi
}

# Function to train a model and upload to Hugging Face
train_model() {
  local size=$1
  local steps=$2
  local batch_size=$3
  local hf_repo=$4
  local output_dir="./tmp/${size}"
  local log_file="training_${size}.log"

  echo "========================================================"
  echo "Starting ${size} model training"
  echo "Steps: ${steps}, Batch size: ${batch_size}"
  echo "Output directory: ${output_dir}"
  echo "Hugging Face repo: ${hf_repo}"
  echo "========================================================"

  # Clean output directory if it exists
  if [ -d "${output_dir}" ]; then
    echo "Cleaning output directory: ${output_dir}"
    rm -rf "${output_dir}/*"
  fi

  # Launch training with parameters for this model size
  ./run_all.py \
    --model_size ${size} \
    --dataset code-mix \
    --batch_size ${batch_size} \
    --steps ${steps} \
    --learning_rate 0.0001 \
    --max_seq_length 131072 \
    --use_flash_attention \
    --use_reasoning_layer \
    --num_checkpoints 3 \
    --output_dir ${output_dir} \
    --push_to_hub \
    --hf_repo ${hf_repo} \
    --debug \
    --force > ${log_file} 2>&1

  # Check if training was successful
  if check_training_success ${log_file}; then
    echo "Training ${size} model completed successfully!"
    echo "Model uploaded to Hugging Face: ${hf_repo}"

    # Clean up to save space
    echo "Cleaning up local files to save space"
    find ${output_dir} -type f -name "*.bin" -delete
    find ${output_dir} -type f -name "*.msgpack" -delete

    return 0
  else
    echo "Training ${size} model failed. Check ${log_file} for details."
    return 1
  fi
}

# Start with 7B model and upload to Hugging Face
echo "========================================================"
echo "PHASE 1: Training 7B model and uploading to Hugging Face"
echo "========================================================"

# Train 7B model with fewer steps (faster to train)
if train_model "7b" 50000 64 "igitgamerz38/llm-7b-code"; then
  echo "7B model trained and uploaded successfully to Hugging Face!"
else
  echo "Failed to train 7B model. Exiting."
  exit 1
fi

# Continue with larger models
echo "========================================================"
echo "PHASE 2: Training 13B model"
echo "========================================================"

# Train 13B model
train_model "13b" 100000 48 "igitgamerz38/llm-13b-code"

echo "========================================================"
echo "PHASE 3: Training 70B model"
echo "========================================================"

# Train 70B model
train_model "70b" 200000 32 "igitgamerz38/llm-70b-code"

echo "========================================================"
echo "PHASE 4: Training 175B model"
echo "========================================================"

# Train 175B model
train_model "175b" 400000 32 "igitgamerz38/llm-175b-code"

echo "========================================================"
echo "All models trained successfully!"
echo "========================================================"

# Summary
echo "Training summary:"
echo "- 7B model: https://huggingface.co/igitgamerz38/llm-7b-code"
echo "- 13B model: https://huggingface.co/igitgamerz38/llm-13b-code"
echo "- 70B model: https://huggingface.co/igitgamerz38/llm-70b-code"
echo "- 175B model: https://huggingface.co/igitgamerz38/llm-175b-code"
echo ""
echo "Check individual log files for details:"
echo "- training_7b.log"
echo "- training_13b.log"
echo "- training_70b.log"
echo "- training_175b.log"

# Clean up temporary directories to save space
echo "Cleaning up temporary directories to save space"
rm -rf ./tmp/*
