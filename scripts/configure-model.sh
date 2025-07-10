#!/bin/bash

# Model Service Configuration Script
# This script configures the ModelService for optimal performance on GKE

set -e

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "ERROR: .env file not found. Please run setup-env.sh first."
    exit 1
fi

echo "Configuring ModelService: $MODEL_NAME"

# Wait for ModelService to be created
echo "Waiting for ModelService to be available..."
while ! kubectl get modelservice "$MODEL_NAME" &> /dev/null; do
    echo "Waiting for ModelService $MODEL_NAME to be created..."
    sleep 5
done

echo "ModelService $MODEL_NAME found! Applying configurations..."

# Fix PATH and LD_LIBRARY_PATH for GKE compatibility
echo "Fixing PATH and LD_LIBRARY_PATH for GKE compatibility..."

# Patch decode containers
kubectl patch ModelService "$MODEL_NAME" --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/decode/containers/0/env/-",
    "value": {
      "name": "PATH",
      "value": "/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/workspace/vllm/.vllm/bin:/root/.local/bin:/usr/local/ompi/bin"
    }
  },
  {
    "op": "add",
    "path": "/spec/decode/containers/0/env/-",
    "value": {
      "name": "LD_LIBRARY_PATH",
      "value": "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/nixl/lib/x86_64-linux-gnu/:/usr/local/ompi/lib:/usr/lib:/usr/local/lib"
    }
  }
]'

# Patch prefill containers
kubectl patch ModelService "$MODEL_NAME" --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/prefill/containers/0/env/-",
    "value": {
      "name": "PATH",
      "value": "/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/workspace/vllm/.vllm/bin:/root/.local/bin:/usr/local/ompi/bin"
    }
  },
  {
    "op": "add",
    "path": "/spec/prefill/containers/0/env/-",
    "value": {
      "name": "LD_LIBRARY_PATH",
      "value": "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/nixl/lib/x86_64-linux-gnu/:/usr/local/ompi/lib:/usr/lib:/usr/local/lib"
    }
  }
]'

echo "Environment variables configured successfully!"

# Optional: Optimize for L4 GPU architecture
echo "Skipping L4 GPU optimizations (commented out)..."

# Add GPU memory utilization setting
# kubectl patch ModelService "$MODEL_NAME" --type='json' -p='[
#   {
#     "op": "add",
#     "path": "/spec/decode/containers/0/args/-",
#     "value": "--gpu-memory-utilization=0.95"
#   }
# ]'

# Add max model length setting to prevent OOM
# kubectl patch ModelService "$MODEL_NAME" --type='json' -p='[
#   {
#     "op": "add",
#     "path": "/spec/decode/containers/0/args/-",
#     "value": "--max-model-len=65536"
#   }
# ]'

echo "L4 GPU optimizations skipped (uncomment above patches if needed)!"

# Wait for ModelService to restart with new configuration
echo "Waiting for ModelService to restart with new configuration..."
kubectl rollout status deployment "$MODEL_NAME-decode" --timeout=300s
kubectl rollout status deployment "$MODEL_NAME-prefill" --timeout=300s

echo "ModelService configuration completed successfully!"

# Show current ModelService status
echo "ModelService status:"
kubectl get modelservice "$MODEL_NAME" -o wide
kubectl get pods -l app.kubernetes.io/name="$MODEL_NAME"

echo "ModelService $MODEL_NAME is ready for testing!"