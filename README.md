# gke-llm-d
## Set up your environment settings
```bash
# Google Cloud Platform settings
export PROJECT_ID="gpu-launchpad-playground"
export REGION="us-central1"

# GKE Cluster settings
export CLUSTER_NAME="mwy-llm-d"

# GKE Node Pool settings
export NODE_LOCATIONS="us-central1-a,us-central1-b,us-central1-c"
export NODEPOOL_NAME="mwy-llm-d-h100"
export MACHINE_TYPE="a3-highgpu-1g"
export GPU_TYPE="nvidia-h100-80gb"
export GPU_COUNT=1 # Number of GPUs to attach per VM
export GPU_DRIVER_VERSION="latest" # Use "latest" or a specific version

# Nodepool Autoscaling settings
export MIN_NODES=0
export MAX_NODES=4
export INITIAL_NODES=1
```

## Create Cluster
```bash
gcloud beta container --project "$PROJECT_ID" clusters create "$CLUSTER_NAME" \
    --region "$REGION" \
    --cluster-version="$GKE_VERSION" \
    --enable-dataplane-v2 \
    --enable-dataplane-v2-metrics \
    --enable-dataplane-v2-flow-observability \
    --addons HorizontalPodAutoscaling,HttpLoadBalancing,NodeLocalDNS,GcePersistentDiskCsiDriver,GcsFuseCsiDriver \
    --enable-managed-prometheus \
    --workload-pool "${PROJECT_ID}.svc.id.goog" \
    --enable-shielded-nodes \
    --shielded-integrity-monitoring \
    --no-shielded-secure-boot \
    --enable-multi-networking
```
## Create GPU Nodepool
```bash
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
```

## Clone llm-d git repo & install dependencies
```bash
git clone https://github.com/llm-d/llm-d-deployer.git
cd llm-d-deployer/quickstart
./install-deps.sh
```

## Set up Huggingface token environment variable
```bash
export HF_TOKEN=${INSERT YOUR TOKEN HERE}
```

Make sure you have requested access to the https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct model.

## Set up GKE Inference Gateway
