#!/bin/bash

# Cleanup Script for LLM-D Deployment
# This script removes all resources created during the deployment

set -e

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "ERROR: .env file not found. Please run setup-env.sh first."
    exit 1
fi

echo "Starting cleanup of LLM-D deployment..."
echo "Project: $PROJECT_ID"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"

# Function to clean up Kubernetes resources
cleanup_k8s_resources() {
    echo "=== Cleaning up Kubernetes resources ==="
    
    # Delete specific resources
    echo "Deleting HealthCheckPolicy, Gateway, GCPBackendPolicy, HTTPRoute resources..."
    kubectl delete HealthCheckPolicy,Gateway,GCPBackendPolicy,HTTPRoute --all --ignore-not-found=true
    
    # Uninstall Helm releases
    echo "Uninstalling Helm releases..."
    helm uninstall llm-d-sample --ignore-not-found 2>/dev/null || echo "llm-d-sample not found"
    helm uninstall llm-d --ignore-not-found 2>/dev/null || echo "llm-d not found"
    
    # Delete ModelServices
    echo "Deleting ModelServices..."
    kubectl delete modelservice --all --ignore-not-found=true
    
    # Delete secrets
    echo "Deleting secrets..."
    kubectl delete secret llm-d-hf-token --ignore-not-found=true
    
    # Delete RBAC resources
    echo "Deleting RBAC resources..."
    kubectl delete clusterrole inference-gateway-metrics-reader --ignore-not-found=true
    kubectl delete clusterrole gmp-system-collector-read-secrets --ignore-not-found=true
    kubectl delete clusterrolebinding inference-gateway-sa-metrics-reader-role-binding --ignore-not-found=true
    kubectl delete clusterrolebinding gmp-system-collector-secret-reader --ignore-not-found=true
    kubectl delete serviceaccount inference-gateway-sa-metrics-reader --ignore-not-found=true
    
    # Delete Gateway API CRDs (optional - uncomment if you want to remove them)
    # echo "Deleting Gateway API CRDs..."
    # kubectl delete -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v0.3.0/manifests.yaml --ignore-not-found=true
    
    echo "Kubernetes resources cleanup completed!"
}

# Function to delete the entire GKE cluster
delete_cluster() {
    echo "=== Deleting GKE cluster ==="
    echo "This will delete the entire cluster: $CLUSTER_NAME"
    echo "Are you sure you want to continue? (y/N)"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Deleting GKE cluster..."
        gcloud container clusters delete "$CLUSTER_NAME" --region "$REGION" --quiet
        echo "GKE cluster deleted successfully!"
    else
        echo "Cluster deletion cancelled."
    fi
}


# Main cleanup function
main_cleanup() {
    echo "Choose cleanup option:"
    echo "1. Clean up Kubernetes resources only"
    echo "2. Delete entire GKE cluster"
    echo "3. Cancel"
    
    read -r choice
    
    case $choice in
        1)
            cleanup_k8s_resources
            ;;
        2)
            delete_cluster
            ;;
        3)
            echo "Cleanup cancelled."
            exit 0
            ;;
        *)
            echo "Invalid choice. Exiting."
            exit 1
            ;;
    esac
}

# Command line argument handling
case "${1:-}" in
    "k8s"|"kubernetes")
        cleanup_k8s_resources
        ;;
    "cluster")
        delete_cluster
        ;;
    *)
        main_cleanup
        ;;
esac

echo "Cleanup completed!"