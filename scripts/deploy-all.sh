#!/bin/bash

# Main Deployment Script for LLM-D on GKE
# This script orchestrates the complete deployment process

set -e

echo "🚀 Starting LLM-D deployment on GKE..."

# Check if all required scripts exist
REQUIRED_SCRIPTS=(
    "scripts/setup-env.sh"
    "scripts/install-deps.sh"
    "scripts/create-cluster.sh"
    "scripts/setup-k8s.sh"
    "scripts/deploy-llm-d.sh"
    "scripts/configure-model.sh"
    "scripts/test-deployment.sh"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ ! -f "$script" ]; then
        echo "ERROR: Required script $script not found"
        exit 1
    fi
done

echo "✅ All required scripts found"

# Step 1: Environment setup
echo "📋 Step 1: Setting up environment..."
./scripts/setup-env.sh

# Step 2: Install dependencies
echo "📦 Step 2: Installing dependencies..."
./scripts/install-deps.sh

# Step 3: Create GKE cluster
echo "🏗️  Step 3: Creating GKE cluster..."
./scripts/create-cluster.sh

# Step 4: Setup Kubernetes configurations
echo "⚙️  Step 4: Setting up Kubernetes configurations..."
./scripts/setup-k8s.sh

# Step 5: Deploy LLM-D
echo "🚀 Step 5: Deploying LLM-D..."
./scripts/deploy-llm-d.sh

# Step 6: Configure model service
echo "🔧 Step 6: Configuring model service..."
./scripts/configure-model.sh

# Step 7: Test deployment
echo "🧪 Step 7: Testing deployment..."
./scripts/test-deployment.sh

echo "🎉 LLM-D deployment completed successfully!"
echo ""
echo "Next steps:"
echo "1. Test your deployment: ./scripts/test-deployment.sh"
echo "2. Test external access: ./scripts/test-deployment.sh external"
echo "3. Monitor your deployment: kubectl get pods -w"
echo "4. Clean up when done: ./scripts/cleanup.sh"