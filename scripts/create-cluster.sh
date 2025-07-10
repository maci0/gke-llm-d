#!/bin/bash

# GKE Cluster Creation Script for LLM-D Deployment
# This script creates the GKE cluster and GPU nodepool

set -e

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "ERROR: .env file not found. Please run setup-env.sh first."
    exit 1
fi

# Source the setup script to ensure all variables are set
source scripts/setup-env.sh

echo "Creating GKE cluster: $CLUSTER_NAME"
echo "Project: $PROJECT_ID"
echo "Region: $REGION"

# Create the GKE Cluster
echo "Creating GKE cluster..."
gcloud beta container --project "$PROJECT_ID" clusters create "$CLUSTER_NAME" \
    --region "$REGION" \
    --machine-type=e2-standard-4 \
    --num-nodes=1 \
    --enable-dataplane-v2 \
    --enable-dataplane-v2-metrics \
    --enable-dataplane-v2-flow-observability \
    --addons HorizontalPodAutoscaling,HttpLoadBalancing,NodeLocalDNS,GcePersistentDiskCsiDriver,GcsFuseCsiDriver \
    --enable-managed-prometheus \
    --workload-pool "${PROJECT_ID}.svc.id.goog" \
    --enable-shielded-nodes \
    --shielded-integrity-monitoring \
    --no-shielded-secure-boot \
    --enable-multi-networking \
    --gateway-api=standard

echo "Cluster created successfully!"

# Create the GPU Nodepool
echo "Creating GPU nodepool: $NODEPOOL_NAME"
gcloud beta container --project "$PROJECT_ID" node-pools create "$NODEPOOL_NAME" \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --node-locations "$NODE_LOCATIONS" \
    --machine-type "$MACHINE_TYPE" \
    --accelerator "type=$GPU_TYPE,count=$GPU_COUNT,gpu-driver-version=$GPU_DRIVER_VERSION" \
    --num-nodes "$INITIAL_NODES" \
    --enable-autoscaling \
    --min-nodes "$MIN_NODES" \
    --max-nodes "$MAX_NODES" \
    --max-surge-upgrade 1 \
    --max-unavailable-upgrade 0 \
    --shielded-integrity-monitoring \
    --shielded-secure-boot

echo "GPU nodepool created successfully!"

# Get cluster credentials
echo "Getting cluster credentials..."
gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION" --project "$PROJECT_ID"

echo "Cluster creation completed successfully!"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "GPU Nodepool: $NODEPOOL_NAME"
echo "GPU Type: $GPU_TYPE"
echo "Max Nodes: $MAX_NODES"

# Verify cluster status
echo "Verifying cluster status..."
kubectl get nodes
kubectl get pods --all-namespaces