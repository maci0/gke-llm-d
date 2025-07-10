#!/bin/bash

# Kubernetes Configuration Script for LLM-D Deployment
# This script sets up Kubernetes configurations, secrets, and CRDs

set -e

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "ERROR: .env file not found. Please run setup-env.sh first."
    exit 1
fi

echo "Setting up Kubernetes configurations..."

# Create Hugging Face Token Secret
echo "Creating Hugging Face token secret..."
if kubectl get secret llm-d-hf-token &> /dev/null; then
    echo "Secret llm-d-hf-token already exists, deleting and recreating..."
    kubectl delete secret llm-d-hf-token
fi

kubectl create secret generic llm-d-hf-token \
    --from-literal="HF_TOKEN=${HF_TOKEN}"

echo "Hugging Face token secret created successfully!"

# Install Gateway API Inference Extension
echo "Installing Gateway API Inference Extension..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v0.3.0/manifests.yaml

# Set up RBAC for metrics scraping
echo "Setting up RBAC for metrics scraping..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: inference-gateway-metrics-reader
rules:
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: inference-gateway-sa-metrics-reader
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: inference-gateway-sa-metrics-reader-role-binding
subjects:
- kind: ServiceAccount
  name: inference-gateway-sa-metrics-reader
  namespace: default
roleRef:
  kind: ClusterRole
  name: inference-gateway-metrics-reader
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: gmp-system-collector-read-secrets
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gmp-system-collector-secret-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: gmp-system-collector-read-secrets
subjects:
- kind: ServiceAccount
  name: collector
  namespace: gmp-system
EOF

echo "RBAC configurations applied successfully!"

# Verify the setup
echo "Verifying Kubernetes setup..."
kubectl get secrets | grep llm-d-hf-token
kubectl get crd | grep -i gateway
kubectl get clusterroles | grep -E "(inference-gateway|gmp-system)"

echo "Kubernetes configuration completed successfully!"
echo "Ready to deploy llm-d components!"