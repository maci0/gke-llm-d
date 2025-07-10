#!/bin/bash

# Environment Setup Script for GKE LLM-D Deployment
# This script sets up all necessary environment variables for the deployment

set -e

echo "Setting up environment variables for GKE LLM-D deployment..."

# Check if .env file exists, if not create it
if [ ! -f .env ]; then
    echo "Creating .env file with default values..."
    cat > .env << 'EOF'
# Google Cloud Platform Settings
PROJECT_ID="gpu-launchpad-playground"
REGION="us-central1"

# GKE Cluster Settings
CLUSTER_NAME="mwy-llm-d"

# GKE Node Pool Settings
NODE_LOCATIONS="us-central1-a,us-central1-b,us-central1-c"
NODEPOOL_NAME="mwy-llm-d-l4"
MACHINE_TYPE="g2-standard-8"
GPU_TYPE="nvidia-l4"
GPU_COUNT=1
GPU_DRIVER_VERSION="latest"

# Nodepool Autoscaling Settings
MIN_NODES=0
MAX_NODES=4
INITIAL_NODES=1

# Hugging Face Token (REPLACE WITH YOUR ACTUAL TOKEN)
HF_TOKEN="<INSERT YOUR TOKEN HERE>"

# Model Settings
MODEL_ID="meta-llama/Llama-3.2-1B-Instruct"
MODEL_NAME="llama-3-2-1b-instruct"
EOF
    echo "Created .env file. Please edit it with your specific values, especially the HF_TOKEN!"
else
    echo "Found existing .env file"
fi

# Source the environment file
source .env

# Export all variables
export PROJECT_ID
export REGION
export CLUSTER_NAME
export NODE_LOCATIONS
export NODEPOOL_NAME
export MACHINE_TYPE
export GPU_TYPE
export GPU_COUNT
export GPU_DRIVER_VERSION
export MIN_NODES
export MAX_NODES
export INITIAL_NODES
export HF_TOKEN
export MODEL_ID
export MODEL_NAME

# Validate required environment variables
echo "Validating environment variables..."

if [ -z "$PROJECT_ID" ]; then
    echo "ERROR: PROJECT_ID is not set"
    exit 1
fi

if [ -z "$HF_TOKEN" ] || [ "$HF_TOKEN" = "<INSERT YOUR TOKEN HERE>" ]; then
    echo "ERROR: HF_TOKEN is not set or still has placeholder value"
    echo "Please edit .env file and set your actual Hugging Face token"
    exit 1
fi

# Check if gcloud is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo "ERROR: No active gcloud authentication found"
    echo "Please run: gcloud auth login"
    exit 1
fi

# Set the project
gcloud config set project "$PROJECT_ID"

echo "Environment setup completed successfully!"
echo "Current settings:"
echo "  PROJECT_ID: $PROJECT_ID"
echo "  REGION: $REGION"
echo "  CLUSTER_NAME: $CLUSTER_NAME"
echo "  MODEL_ID: $MODEL_ID"
echo "  MODEL_NAME: $MODEL_NAME"
echo ""
echo "Ready to proceed with cluster creation!"