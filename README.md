# Deploying a Large Language Model with llm-d on Google Kubernetes Engine (GKE)

This guide provides step-by-step instructions for deploying a large language model using the `llm-d` architecture on a GKE cluster with GPU acceleration.

## Table of Contents

- [TL;DR - Quick Start](#tldr---quick-start-with-automation-scripts)
- [Prerequisites](#prerequisites)
- [Architecture Overview](#architecture-overview)
- [Manual Deployment Guide](#manual-deployment-guide)
- [Advanced Usage](#advanced-usage)
- [Troubleshooting](#troubleshooting)

## TL;DR - Quick Start with Automation Scripts

🚀 **Want to deploy quickly?** Use our automated scripts:

```bash
# 1. Setup environment (edit .env file with your tokens)
./scripts/setup-env.sh

# 2. Complete automated deployment
./scripts/deploy-all.sh

# 3. Test your deployment
./scripts/test-deployment.sh

# 4. Clean up when done
./scripts/cleanup.sh
```

📖 **For detailed script documentation, see [scripts/README.md](scripts/README.md)**

### Prerequisites for Quick Start

- **Google Cloud SDK** (gcloud) - [Install Guide](https://cloud.google.com/sdk/docs/install)
- **kubectl** - [Install Guide](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- **Helm** - [Install Guide](https://helm.sh/docs/intro/install/)
- **Hugging Face Token** - Get from [Hugging Face Settings](https://huggingface.co/settings/tokens)
- **Model Access** - Request access to [meta-llama/Llama-3.2-1B-Instruct](https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct)

---

## Architecture Overview

This deployment creates:
- **GKE Cluster** with GPU-enabled nodes (NVIDIA L4)
- **LLM-D Stack**: Kubernetes-native distributed inference serving platform
  - **Model Service**: Manages model lifecycle and inference workloads
  - **Gateway**: Routes requests and provides load balancing
  - **Redis**: Handles caching and session management
  - **vLLM**: High-performance inference engine with prefill/decode separation
---

## Manual Deployment Guide

The sections below provide detailed manual instructions for understanding each step:

## Prerequisites

Before you begin, ensure you have the following:

### Required Tools
- **Google Cloud SDK (gcloud)** - [Install Guide](https://cloud.google.com/sdk/docs/install)
  - Must be authenticated: `gcloud auth login`
  - Must have required permissions (see [IAM Requirements](#iam-requirements))
- **kubectl** - [Install Guide](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- **Helm** - [Install Guide](https://helm.sh/docs/intro/install/)

### Required Accounts & Access
- **Google Cloud Project** with billing enabled
- **Hugging Face Account** with access token - [Get Token](https://huggingface.co/settings/tokens)
- **Model Access** - Request access to [meta-llama/Llama-3.2-1B-Instruct](https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct)

### IAM Requirements

Your Google Cloud user/service account needs the following roles:
- `roles/container.admin` (GKE administration)
- `roles/compute.admin` (VM and network management)
- `roles/iam.serviceAccountUser` (Service account usage)
- `roles/serviceusage.serviceUsageAdmin` (Enable APIs)

### Resource Quotas

Ensure your project has sufficient quotas:
- **GPU Quota**: At least 1 NVIDIA L4 GPU in your chosen region (can scale up to 4)
- **CPU Quota**: At least 16 vCPUs
- **Persistent Disk**: At least 200GB SSD

> **💡 Tip**: Check quotas in [GCP Console](https://console.cloud.google.com/iam-admin/quotas)

## 2. Environment Configuration
First, set up the environment variables that will be used throughout the deployment process.
```bash
# --- Google Cloud Platform Settings ---
export PROJECT_ID="gpu-launchpad-playground"
export PROJECT="$PROJECT_ID"
export REGION="us-central1"

# --- GKE Cluster Settings ---
export CLUSTER_NAME="mwy-llm-d"

# --- GKE Node Pool Settings ---
export NODE_LOCATIONS="us-central1-a"
export NODEPOOL_NAME="mwy-llm-d-a3u"
export MACHINE_TYPE="a3-ultragpu-8g"
export GPU_TYPE="nvidia-h200-141gb"
export GPU_COUNT=1 # Number of GPUs to attach per VM
export GPU_DRIVER_VERSION="latest" # Use "latest" or a specific version
export GVNIC_NETWORK_PREFIX="$NODEPOOL_NAME-gvnic"
export RDMA_NETWORK_PREFIX="$NODEPOOL_NAME-rdma"

# --- Nodepool Autoscaling Settings ---
export MIN_NODES=0
export MAX_NODES=4
export INITIAL_NODES=1
```
**Important**: Set your Hugging Face token:
```bash
# --- Hugging Face Token ---
# Replace with your actual Hugging Face token
export HF_TOKEN="<INSERT YOUR TOKEN HERE>"
```

> **⚠️ Security Note**: Never commit your actual token to version control. The automated scripts create a `.env` file which is gitignored.

## 3. Infrastructure Setup
Next, create the GKE cluster and a dedicated GPU node pool.

### Create the additional RDMA networks
Reference: https://cloud.google.com/ai-hypercomputer/docs/create/gke-ai-hypercompute

```bash
# Create a VPC for the additional Google Titanium CPU NIC
gcloud compute --project=${PROJECT?} \
  networks create \
  ${GVNIC_NETWORK_PREFIX?}-net \
  --subnet-mode=custom

gcloud compute --project=${PROJECT?} \
  networks subnets create \
  ${GVNIC_NETWORK_PREFIX?}-sub \
  --network=${GVNIC_NETWORK_PREFIX?}-net \
  --region=${REGION?} \
  --range=192.168.0.0/24

gcloud compute --project=${PROJECT?} \
  firewall-rules create \
  ${GVNIC_NETWORK_PREFIX?}-internal \
  --network=${GVNIC_NETWORK_PREFIX?}-net \
  --action=ALLOW \
  --rules=tcp:0-65535,udp:0-65535,icmp \
  --source-ranges=192.168.0.0/16

# Create HPC VPC for the RDMA NICs with 8 subnets.
gcloud beta compute --project=${PROJECT?} \
  networks create ${RDMA_NETWORK_PREFIX?}-net \
  --network-profile=${ZONE?}-vpc-roce \
  --subnet-mode=custom

# Create subnets for the HPC VPC.
for N in $(seq 0 7); do
  gcloud compute --project=${PROJECT?} \
    networks subnets create \
    ${RDMA_NETWORK_PREFIX?}-sub-$N \
    --network=${RDMA_NETWORK_PREFIX?}-net \
    --region=${REGION?} \
    --range=192.168.$((N+1)).0/24 &  # offset to avoid overlap with gvnics
done
```

### Create the GKE Cluster
This command creates a standard GKE cluster that will host the control plane and other supporting services.
```bash
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
    --enable-ip-alias \
    --gateway-api=standard
```
### Create the GPU Nodepool
This nodepool is specifically configured with GPUs to run the LLM inference workloads.
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

## 4. llm-d and Dependency Installation
Now, prepare your environment by cloning the necessary repository and installing dependencies.
```bash
git clone https://github.com/llm-d/llm-d-deployer.git
cd llm-d-deployer/quickstart
./install-deps.sh

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add llm-d https://llm-d.ai/llm-d-deployer
helm repo update
```

## 5. Kubernetes Configuration

### Create Hugging Face Token Secret

Create a Kubernetes secret to securely store your Hugging Face token. This will be used by `llm-d` to download the model.

```bash
kubectl create secret generic llm-d-hf-token \
    --from-literal="HF_TOKEN=${HF_TOKEN}"
```

### Set up GKE Inference Gateway CRD and RBAC
Apply the necessary manifests for the GKE Inference Gateway and configure the required Role-Based Access Control (RBAC) for metrics scraping.
```bash
# Install the Gateway API Inference Extension
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v0.3.0/manifests.yaml

# Set up authorization for the metrics scraper
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

```

## 6. llm-d Configuration
Create the configuration files for the llm-d core components and the sample application.

### Configure Core llm-d Services
This configuration enables the necessary backend services for `llm-d`, including Redis for caching and the inference gateway for routing.

```bash
cat <<EOF > llm-d-gke.yaml
sampleApplication:
  enabled: false
gateway:
  enabled: true
  gatewayClassName: gke-l7-rilb
redis:
  enabled: true
modelservice:
  vllm:
    metrics:
      enabled: true
    #image:
      #registry: registry.hub.docker.com
      #repository: vllm/vllm-openai
      #tag: v0.9.1
  epp:
    defaultEnvVarsOverride:
      - name: ENABLE_KVCACHE_AWARE_SCORER
        value: "false"
      - name: ENABLE_PREFIX_AWARE_SCORER
        value: "true"
      - name: ENABLE_LOAD_AWARE_SCORER
        value: "true"
      - name: ENABLE_SESSION_AWARE_SCORER
        value: "false"
      - name: PD_ENABLED
        value: "false"
      - name: PD_PROMPT_LEN_THRESHOLD
        value: "10"
      - name: PREFILL_ENABLE_KVCACHE_AWARE_SCORER
        value: "true"
      - name: PREFILL_ENABLE_LOAD_AWARE_SCORER
        value: "false"
      - name: PREFILL_ENABLE_PREFIX_AWARE_SCORER
        value: "true"
      - name: PREFILL_ENABLE_SESSION_AWARE_SCORER
        value: "true"
  metrics:
    enabled: false
EOF
```

### Configure the llm-d Sample Application
This configuration defines the model that will be deployed.
We are using the `basic-gpu-preset` base configmap.
You can view it running `kubectl get cm basic-gpu-preset -o yaml`
```bash

export MODEL_ID="meta-llama/Llama-3.2-1B-Instruct"
# A Kubernetes-friendly name for the model resources
export MODEL_NAME="llama-3-2-1b-instruct"

cat <<EOF > llm-d-sample.yaml
sampleApplication:
  enabled: true
  baseConfigMapRefName: basic-gpu-preset
  model:
    modelArtifactURI: "hf://${MODEL_ID}"
    modelName: "${MODEL_NAME}"
gateway:
  enabled: true
  gatewayClassName: gke-l7-rilb
modelservice:
  enabled: false
redis:
  enabled: false
EOF
```

## 7. Deploy llm-d
Install the llm-d components using Helm and the configurations you just created.
```bash
helm install llm-d llm-d/llm-d -f llm-d-gke.yaml
helm install llm-d-sample llm-d/llm-d -f llm-d-sample.yaml 
```

## 8. Model Service Adjustments (Critical for GKE)

> **⚠️ Important**: This step is required for GKE compatibility. Until https://github.com/llm-d/llm-d/pull/123 is merged
The `llm-d` image used by the default configuration does not work out of the box on GKE.
This can be fixed by adjusting the `PATH` and `LD_LIBRARY_PATH` variables in the `ModelService`

```bash
kubectl patch ModelService ${MODEL_NAME} --type='json' -p='[{"op": "add", "path": "/spec/decode/containers/0/env/-", "value": {"name": "PATH", "value": "/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/workspace/vllm/.vllm/bin:/root/.local/bin:/usr/local/ompi/bin"}}, {"op": "add", "path": "/spec/decode/containers/0/env/-", "value": {"name": "LD_LIBRARY_PATH", "value": "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/nixl/lib/x86_64-linux-gnu/:/usr/local/ompi/lib:/usr/lib:/usr/local/lib"}}]'

kubectl patch ModelService ${MODEL_NAME} --type='json' -p='[{"op": "add", "path": "/spec/prefill/containers/0/env/-", "value": {"name": "PATH", "value": "/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/workspace/vllm/.vllm/bin:/root/.local/bin:/usr/local/ompi/bin"}}, {"op": "add", "path": "/spec/prefill/containers/0/env/-", "value": {"name": "LD_LIBRARY_PATH", "value": "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/nixl/lib/x86_64-linux-gnu/:/usr/local/ompi/lib:/usr/lib:/usr/local/lib"}}]'
```


### Optimize for the L4 GPU architecture ( Optional )
You may need to adjust the `ModelService` to optimize for the L4 GPU architecture.

To prevent out-of-memory errors, you can add arguments to the vllm startup command. For example, to set the GPU memory utilization:
```bash
# This is an example patch. The name of the ModelService might differ.
kubectl patch ModelService ${MODEL_NAME} --type='json' -p='[{"op": "add", "path": "/spec/decode/containers/0/args/-", "value": "--gpu-memory-utilization=0.95"}]'
```
Alternatively, you could reduce the maximum model length (context window):
```bash
# This is an example patch. The name of the ModelService might differ.
kubectl patch ModelService ${MODEL_NAME} --type='json' -p='[{"op": "add", "path": "/spec/decode/containers/0/args/-", "value": "--max-model-len=65536"}]'
```



## 9. Testing the Deployment

Once the deployment is complete, you can test it by sending a completion request.

### Verify Deployment Status

First, check that all components are running:

```bash
# Check pods
kubectl get pods -l app.kubernetes.io/name=llm-d

# Check ModelService
kubectl get modelservices

# Check Gateway
kubectl get gateways
```

### Test with Automated Script

```bash
# Use the automated test script
./scripts/test-deployment.sh
```

This will test:
1. Direct pod access to the model
2. Gateway access (if configured)
3. Model availability and inference

### Example Test Output

```json
{
  "choices": [
    {
      "finish_reason": "length",
      "index": 0,
      "text": " I'm a curious person, and I'm interested in learning more about the world"
    }
  ],
  "model": "llama-3-2-1b-instruct",
  "object": "text_completion",
  "usage": {
    "completion_tokens": 16,
    "prompt_tokens": 5,
    "total_tokens": 21
  }
}
```

### Manual testing
This will only work from the same region.
```bash
IP=$(kubectl get gateway/${MODEL_NAME}-gateway -o jsonpath='{.status.addresses[0].value}')
PORT=80 # Use 80 for HTTP

curl -i -X POST ${IP}:${PORT}/v1/completions \
-H 'Content-Type: application/json' \
-H "Authorization: Bearer $(gcloud auth print-access-token)" \
-d "{
    \"model\": \"${MODEL_NAME}\",
    \"prompt\": \"Say something\",
    \"max_tokens\": 8124,
    \"temperature\": \"0.5\"
}"
```

## 10. Cleanup

### Option 1: Use Automated Cleanup

```bash
# Interactive cleanup with options
./scripts/cleanup.sh

# Or specific cleanup commands:
./scripts/cleanup.sh k8s      # Remove K8s resources only
./scripts/cleanup.sh cluster  # Delete entire cluster
```

### Option 2: Manual Cleanup

```bash
# Remove Kubernetes resources
kubectl delete HealthCheckPolicy,Gateway,GCPBackendPolicy,HTTPRoute --all
helm uninstall llm-d-sample
helm uninstall llm-d

# Delete the entire cluster
gcloud container clusters delete "$CLUSTER_NAME" --region "$REGION"
```

> **💡 Tip**: The automated cleanup script provides interactive options and safety checks.



---

## Advanced Usage

### Adding Additional Models

This example shows how to manually create another ModelService:
```yaml
export SERVED_MODEL_NAME=qwen3-0-6b
export MODEL="Qwen/Qwen3-0.6B"
export MODEL_URI="hf://${MODEL}"

kubectl apply -f - <<EOF
apiVersion: llm-d.ai/v1alpha1
kind: ModelService
metadata:
  name: ${SERVED_MODEL_NAME}
spec:
  modelArtifacts:
    uri: ${MODEL_URI}
  decoupleScaling: false
  baseConfigMapRef:
    name: basic-gpu-with-nixl-preset
  routing:
    modelName: ${SERVED_MODEL_NAME}
  decode:
    replicas: 1
    containers:
    - name: "vllm"
      resources:
        limits:
          nvidia.com/gpu: "1"
        requests:
          nvidia.com/gpu: "1"
      args:
      - "--served-model-name"
      - "${SERVED_MODEL_NAME}"
      env:
      - name: HF_TOKEN
        valueFrom:
          secretKeyRef:
            key: HF_TOKEN
            name: llm-d-hf-token
      - name: PATH
        value: /usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/workspace/vllm/.vllm/bin:/root/.local/bin:/usr/local/ompi/bin
      - name: LD_LIBRARY_PATH
        value: /usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/nixl/lib/x86_64-linux-gnu/:/usr/local/ompi/lib:/usr/lib:/usr/local/lib
  prefill:
    replicas: 1
    containers:
    - name: "vllm"
      resources:
        limits:
          nvidia.com/gpu: "1"
        requests:
          nvidia.com/gpu: "1"
      args:
      - "--served-model-name"
      - "${SERVED_MODEL_NAME}"
      env:
      - name: HF_TOKEN
        valueFrom:
          secretKeyRef:
            key: HF_TOKEN
            name: llm-d-hf-token
      - name: PATH
        value: /usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/workspace/vllm/.vllm/bin:/root/.local/bin:/usr/local/ompi/bin
      - name: LD_LIBRARY_PATH
        value: /usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/nixl/lib/x86_64-linux-gnu/:/usr/local/ompi/lib:/usr/lib:/usr/local/lib
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ${SERVED_MODEL_NAME}-route
spec:
  parentRefs:
  - name: ${SERVED_MODEL_NAME}-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: ${SERVED_MODEL_NAME}-inference-pool
      group: inference.networking.x-k8s.io
      kind: InferencePool
---
apiVersion: networking.gke.io/v1
kind: GCPBackendPolicy
metadata:
  name: ${SERVED_MODEL_NAME}-backend-policy
  namespace: default
spec:
  default:
    logging:
      enabled: true
    timeoutSec: 300
  targetRef:
    group: inference.networking.x-k8s.io
    kind: InferencePool
    name: ${SERVED_MODEL_NAME}-inference-pool
---
kind: HealthCheckPolicy
apiVersion: networking.gke.io/v1
metadata:
  name: ${SERVED_MODEL_NAME}-health-check-policy
  namespace: default
spec:
  targetRef:
    group: "inference.networking.x-k8s.io"
    kind: InferencePool
    name: ${SERVED_MODEL_NAME}-inference-pool
  default:
    config:
      type: HTTP
      httpHealthCheck:
          requestPath: /health
          port: 8000
EOF
```

## Benchmarking

### Install vllm python package
```bash
python -m venv venv
source venv/bin/activate
pip install vllm pandas datasets
git clone --depth=1 https://github.com/vllm-project/vllm.git
```

### Run benchmark
```bash
source venv/bin/activate

export MODEL="Qwen/Qwen3-0.6B"
export SERVED_MODEL_NAME=qwen3-0-6b
export VLLM_HOST=$(kubectl get gateway/${SERVED_MODEL_NAME}-gateway -o jsonpath='{.status.addresses[0].value}')
export VLLM_PORT=80 # Use 80 for HTTP
python3 vllm/benchmarks/benchmark_serving.py --backend vllm --host ${VLLM_HOST} --port ${VLLM_PORT} \
                                        --model ${MODEL} --served-model-name ${SERVED_MODEL_NAME} --dataset-name random \
                                        --random-input-len 2048 --random-output-len 128 \
                                        --num-prompts 1000 --seed 42
```

### Monitoring

Currently, the deployment includes Prometheus metrics from the llm-d components, but **Google Cloud Monitoring (GMP) integration is not yet implemented or tested**.

**Current Status:**
- ✅ **Prometheus metrics** are available from vLLM and llm-d components
- ❌ **Google Cloud Monitoring** integration is pending implementation
- ❌ **Managed Prometheus** integration needs testing

**Available Metrics:**
- vLLM inference metrics (requests, latency, throughput)
- Model service health metrics
- Gateway routing and performance metrics
- Redis cache metrics (if enabled)

**TODO - Future Improvements:**
- Integrate with Google Managed Prometheus (GMP)
- Create Grafana dashboards for visualization
- Set up alerting policies
- Test ClusterPodMonitoring configuration

**Temporary Monitoring:**
You can access raw metrics directly from the pods:
```bash
# Get metrics from vLLM pods
kubectl port-forward <vllm-pod-name> 8000:8000
curl http://localhost:8000/metrics
```

**Reference: ClusterPodMonitoring Configuration (Untested)**

The following configuration is provided as a reference for future GMP integration:

```yaml
kubectl apply -f - <<EOF
apiVersion: monitoring.googleapis.com/v1
kind: ClusterPodMonitoring
metadata:
  name: llm-d-cpm
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: llm-d
  endpoints:
  - port: metrics
    scheme: http
    interval: 5s
    path: /metrics
    authorization:
      type: Bearer
      credentials:
        secret:
          name: inference-gateway-sa-metrics-reader-secret
          key: token
EOF
```

> **⚠️ Note**: This configuration has not been tested and may require adjustments for proper GMP integration.

---

## Troubleshooting

### Common Issues

#### 1. Out of Memory Errors
```bash
# Reduce GPU memory utilization
kubectl patch ModelService ${MODEL_NAME} --type='json' -p='[{"op": "add", "path": "/spec/decode/containers/0/args/-", "value": "--gpu-memory-utilization=0.8"}]'

# Or reduce max model length
kubectl patch ModelService ${MODEL_NAME} --type='json' -p='[{"op": "add", "path": "/spec/decode/containers/0/args/-", "value": "--max-model-len=32768"}]'
```

#### 2. Pod Stuck in Pending State
```bash
# Check GPU node availability
kubectl get nodes -l cloud.google.com/gke-accelerator=nvidia-l4

# Check pod events
kubectl describe pod <pod-name>
```

#### 3. Authentication Issues
```bash
# Verify HF token secret
kubectl get secret llm-d-hf-token -o yaml

# Check model access permissions
kubectl logs <model-pod-name> -c vllm
```

#### 4. Network Issues
```bash
# Test internal connectivity
kubectl run test-curl --rm -i --restart=Never --image=curlimages/curl:latest -- curl -s http://<service-name>:8000/health
```

### Getting Help

- **View logs**: `kubectl logs -l app.kubernetes.io/name=llm-d -f`
- **Check events**: `kubectl get events --sort-by=.metadata.creationTimestamp`
- **Debug pods**: `kubectl describe pod <pod-name>`
- **LLM-D GitHub**: [https://github.com/llm-d/llm-d](https://github.com/llm-d/llm-d)
- **LLM-D Deployer**: [https://github.com/llm-d/llm-d-deployer](https://github.com/llm-d/llm-d-deployer)

### Performance Optimization

1. **GPU Utilization**: Monitor with `nvidia-smi` in pods
2. **Memory Usage**: Adjust `--gpu-memory-utilization` parameter
3. **Batch Size**: Tune `--max-num-seqs` for throughput
4. **Context Length**: Balance `--max-model-len` vs memory usage

---

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with detailed description

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
