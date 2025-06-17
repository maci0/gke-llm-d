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
export NODEPOOL_NAME="mwy-llm-d-l4"
export MACHINE_TYPE="g2-standard-4"
export GPU_TYPE="nvidia-l4"
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
    --enable-multi-networking \
    --gateway-api=standard
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
```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v0.3.0/manifests.yaml


# Set up authorization for the metrics scraper
kubectl apply -f - <<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: inference-gateway-metrics-reader
rules:
- nonResourceURLs:
  - /metrics
  verbs:
  - get
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
  namespace: default
subjects:
- kind: ServiceAccount
  name: inference-gateway-sa-metrics-reader
  namespace: default
roleRef:
  kind: ClusterRole
  name: inference-gateway-metrics-reader
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: Secret
metadata:
  name: inference-gateway-sa-metrics-reader-secret
  namespace: default
  annotations:
    kubernetes.io/service-account.name: inference-gateway-sa-metrics-reader
type: kubernetes.io/service-account-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: inference-gateway-sa-metrics-reader-secret-read
rules:
- resources:
  - secrets
  apiGroups: [""]
  verbs: ["get", "list", "watch"]
  resourceNames: ["inference-gateway-sa-metrics-reader-secret"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gmp-system:collector:inference-gateway-sa-metrics-reader-secret-read
  namespace: default
roleRef:
  name: inference-gateway-sa-metrics-reader-secret-read
  kind: ClusterRole
  apiGroup: rbac.authorization.k8s.io
subjects:
- name: collector
  namespace: gmp-system
  kind: ServiceAccount
EOF

```

## Install llm-d expample workload
```
./llmd-installer.sh -m --values-file ./examples/base.yaml
```

