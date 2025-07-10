#!/bin/bash

# Dependencies Installation Script for LLM-D Deployment
# This script installs all necessary dependencies and repositories

set -e

echo "Installing dependencies for LLM-D deployment..."

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not installed. Please install kubectl first."
    echo "Visit: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
    exit 1
fi

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "ERROR: gcloud is not installed. Please install Google Cloud SDK first."
    echo "Visit: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "ERROR: helm is not installed. Please install Helm first."
    echo "Visit: https://helm.sh/docs/intro/install/"
    exit 1
fi

echo "All required CLI tools are installed!"

# Clone llm-d-deployer repository if it doesn't exist
if [ ! -d "llm-d-deployer" ]; then
    echo "Cloning llm-d-deployer repository..."
    git clone https://github.com/llm-d/llm-d-deployer.git
    cd llm-d-deployer/quickstart
    ./install-deps.sh
    cd ../..
else
    echo "llm-d-deployer repository already exists"
fi

# Add Helm repositories
echo "Adding Helm repositories..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add llm-d https://llm-d.ai/llm-d-deployer
helm repo update

echo "Verifying Helm repositories..."
helm repo list | grep -E "(bitnami|llm-d)"

# Create necessary directories
mkdir -p config/

echo "Dependencies installation completed successfully!"
echo "Available Helm charts:"
helm search repo llm-d