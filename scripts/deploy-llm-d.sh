#!/bin/bash

# LLM-D Deployment Script
# This script deploys the llm-d components and sample application

set -e

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "ERROR: .env file not found. Please run setup-env.sh first."
    exit 1
fi

echo "Deploying LLM-D components..."
echo "Model: $MODEL_ID"
echo "Model Name: $MODEL_NAME"

# Update the llm-d sample configuration with environment variables
echo "Updating llm-d sample configuration..."
sed -i "s|modelArtifactURI: \"hf://.*\"|modelArtifactURI: \"hf://${MODEL_ID}\"|" scripts/config/llm-d-sample.yaml
sed -i "s|modelName: \".*\"|modelName: \"${MODEL_NAME}\"|" scripts/config/llm-d-sample.yaml

echo "Configuration updated successfully!"

# Deploy llm-d core components
echo "Deploying llm-d core components..."
helm install llm-d llm-d/llm-d -f scripts/config/llm-d-gke.yaml

echo "Waiting for core components to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=llm-d --timeout=300s

# Deploy llm-d sample application
echo "Deploying llm-d sample application..."
helm install llm-d-sample llm-d/llm-d -f scripts/config/llm-d-sample.yaml

echo "Waiting for sample application to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=llm-d-sample --timeout=300s

echo "LLM-D deployment completed successfully!"

# Show deployment status
echo "Deployment status:"
kubectl get pods -l app.kubernetes.io/name=llm-d
kubectl get pods -l app.kubernetes.io/name=llm-d-sample
kubectl get services
kubectl get gateways
kubectl get modelservices

echo "Ready to configure model service!"