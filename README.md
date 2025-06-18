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
export MACHINE_TYPE="g2-standard-8"
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

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add llm-d https://llm-d.ai/llm-d-deployer
helm repo add istio https://istio-release.storage.googleapis.com/charts

helm repo update

#helm upgrade -i istio-base istio/base --version 1.26.1 -n istio-system --create-namespace
#helm upgrade -i istiod istio/istiod --version 1.26.1 -n istio-system --wait

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

## Configure llm-d
```bash
cat <<'EOF' > llm-d-gke.yaml
sampleApplication:
  enabled: false
  baseConfigMapRefName: basic-gpu-preset
  model:
    modelArtifactURI: hf://meta-llama/Llama-3.2-3B-Instruct
    modelName: "meta-llama/Llama-3.2-3B-Instruct"
gateway:
  enabled: false	
redis:
  enabled: true
modelservice:
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
        value: "false"
      - name: PREFILL_ENABLE_LOAD_AWARE_SCORER
        value: "false"
      - name: PREFILL_ENABLE_PREFIX_AWARE_SCORER
        value: "false"
      - name: PREFILL_ENABLE_SESSION_AWARE_SCORER
        value: "false"
    metrics:
      enabled: false
  metrics:
    enabled: false
  vllm:
    metrics:
      enabled: false
    #image:

      # -- llm-d image registry
     # registry: registry.hub.docker.com

      # -- llm-d image repository
      #repository: vllm/vllm-openai

      # -- llm-d image tag
      #tag: v0.9.1
EOF

```

## Create huggingface token secret
```bash
kubectl create secret generic llm-d-hf-token \
    --from-literal="HF_TOKEN=${HF_TOKEN}"
```



## Install llm-d
```bash
helm install llm-d llm-d/llm-d -f llm-d-gke.yaml 
```

## install example workload
```yaml
kubectl apply -f - <<EOF
apiVersion: llm-d.ai/v1alpha1
kind: ModelService
metadata:
  name: llama3
spec:
  modelArtifacts:
    uri: hf://meta-llama/Llama-3.2-3B-Instruct
  decoupleScaling: false
  baseConfigMapRef:
    name: basic-gpu-with-nixl-and-redis-lookup-preset
  routing:
    modelName: Llama-3.2-3B-Instruct
  decode:
    replicas: 1
    containers:
    - name: "vllm"
      args:
      - "--model"
      - "meta-llama/Llama-3.2-3B-Instruct"
      - "--max-model-len"
      - "65536"
      env:
      - name: PATH
        value: "/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/workspace/vllm/.vllm/bin:/root/.local/bin:/usr/local/ompi/bin"
      - name: LD_LIBRARY_PATH
        value: "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/cuda/lib64/compat:/usr/local/nixl/lib/x86_64-linux-gnu/:/usr/local/ompi/lib:/usr/lib:/usr/local/lib"
  prefill:
    replicas: 1
    containers:
    - name: "vllm"
      args:
      - "--model"
      - "meta-llama/Llama-3.2-3B-Instruct"
      - "--max-model-len"
      - "65536"
      env:
      - name: PATH
        value: "/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/workspace/vllm/.vllm/bin:/root/.local/bin:/usr/local/ompi/bin"
      - name: LD_LIBRARY_PATH
        value: "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/cuda/lib64/compat:/usr/local/nixl/lib/x86_64-linux-gnu/:/usr/local/ompi/lib:/usr/lib:/usr/local/lib"
EOF
```

## fix PATH and LD_LIBRARY_PATH
```bash
kubectl patch ModelService meta-llama-llama-3-2-3b-instruct --type='json' -p='[{"op": "add", "path": "/spec/decode/containers/0/env/-", "value": {"name": "PATH", "value": "/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/workspace/vllm/.vllm/bin:/root/.local/bin:/usr/local/ompi/bin"}}, {"op": "add", "path": "/spec/decode/containers/0/env/-", "value": {"name": "LD_LIBRARY_PATH", "value": "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/nixl/lib/x86_64-linux-gnu/:/usr/local/ompi/lib:/usr/lib:/usr/local/lib"}}]'

kubectl patch ModelService meta-llama-llama-3-2-3b-instruct --type='json' -p='[{"op": "add", "path": "/spec/prefill/containers/0/env/-", "value": {"name": "PATH", "value": "/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/workspace/vllm/.vllm/bin:/root/.local/bin:/usr/local/ompi/bin"}}, {"op": "add", "path": "/spec/prefill/containers/0/env/-", "value": {"name": "LD_LIBRARY_PATH", "value": "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/nixl/lib/x86_64-linux-gnu/:/usr/local/ompi/lib:/usr/lib:/usr/local/lib"}}]'
```
## Notes
On L4 GPUs probably have to edit the ModelService and add `--gpu-memory-utilization 0.95` to vllm startup options or reduce the context window with like so `--max-model-len 65536`

## Testing
More work to be done here:
```bash
./test-request.sh -n default
Namespace: default
Model ID:  none; will be discover from first entry in /v1/models

1 -> Fetching available models from the decode pod at 10.108.10.7…
{"object":"list","data":[{"id":"meta-llama/Llama-3.2-3B-Instruct","object":"model","created":1750151405,"owned_by":"vllm","root":"meta-llama/Llama-3.2-3B-Instruct","parent":null,"max_model_len":65536,"permission":[{"id":"modelperm-19c52767f53248dd832d8bef1da798d2","object":"model_permission","created":1750151405,"allow_create_engine":false,"allow_sampling":true,"allow_logprobs":true,"allow_search_indices":false,"allow_view":true,"allow_fine_tuning":false,"organization":"*","group":null,"is_blocking":false}]}]}pod "curl-852" deleted

Discovered model to use: meta-llama/Llama-3.2-3B-Instruct

2 -> Sending a completion request to the decode pod at 10.108.10.7…
If you don't see a command prompt, try pressing enter.
warning: couldn't attach to pod/curl-1536, falling back to streaming logs: Internal error occurred: unable to upgrade connection: container curl-1536 not found in pod curl-1536_default
{"id":"cmpl-c63e44d7d17e4d27aced5e324289f28b","object":"text_completion","created":1750151408,"model":"meta-llama/Llama-3.2-3B-Instruct","choices":[{"index":0,"text":" (A question for the ages)\nI am a being of words, a we","logprobs":null,"finish_reason":"length","stop_reason":null,"prompt_logprobs":null}],"usage":{"prompt_tokens":5,"total_tokens":21,"completion_tokens":16,"prompt_tokens_details":null},"kv_transfer_params":null}pod "curl-1536" deleted

3 -> Fetching available models via the gateway at llm-d-inference-gateway-istio.default.svc.cluster.local…
pod "curl-8814" deleted

Error: model 'meta-llama/Llama-3.2-3B-Instruct' not available via gateway:
```



Might also still have to do some more work 
```
kind: HealthCheckPolicy
apiVersion: networking.gke.io/v1
metadata:
  name: {{ .Release.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "gateway-api-inference-extension.labels" . | nindent 4 }}
spec:
  targetRef:
    group: "inference.networking.x-k8s.io"
    kind: InferencePool
    name: {{ .Release.Name }}
  default:
    config:
      type: HTTP
      httpHealthCheck:
          requestPath: /health
          port:  {{ .Values.inferencePool.targetPortNumber }}
---
apiVersion: networking.gke.io/v1
kind: GCPBackendPolicy
metadata:
  name: {{ .Release.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "gateway-api-inference-extension.labels" . | nindent 4 }}
spec:
  targetRef:
    group: "inference.networking.x-k8s.io"
    kind: InferencePool
    name: {{ .Release.Name }}
  default:
    timeoutSec: 300    # 5-minute timeout (adjust as needed)
    logging:
      enabled: true    # log all requests by default
```

##
```
cat <<'EOF' | kubectl apply -f -
kind: HealthCheckPolicy
apiVersion: networking.gke.io/v1
metadata:
  name: llm-d-healthcheck-policy # Use a distinct name
  namespace: default # Ensure this matches your llm-d deployment namespace
spec:
  targetRef:
    group: "inference.networking.x-k8s.io"
    kind: InferencePool
    # The name of the InferencePool is usually derived from the KServe InferenceService or ModelService name.
    # It often follows a pattern like `kserve-<model-service-name>`.
    # Let's verify the InferencePool name after llm-d is deployed.
    # For now, let's assume it matches the llm-d Helm release name for simplicity, but you might need to adjust this.
    name: llama3-inference-pool # This might need to be adjusted to the actual InferencePool name (e.g., kserve-meta-llama-llama-3-2-3b-instruct)
  default:
    config:
      type: HTTP
      httpHealthCheck:
          # llm-d's VLLM endpoint typically exposes health on /health
          requestPath: /health
          port:  8000 # Default VLLM port, adjust if llm-d uses a different internal port
---
apiVersion: networking.gke.io/v1
kind: GCPBackendPolicy
metadata:
  name: llm-d-backend-policy # Use a distinct name
  namespace: default # Ensure this matches your llm-d deployment namespace
spec:
  targetRef:
    group: "inference.networking.x-k8s.io"
    kind: InferencePool
    # As above, verify and adjust the name if needed.
    name: llm-d # This might need to be adjusted
  default:
    timeoutSec: 300    # 5-minute timeout (adjust as needed for long inference)
    logging:
      enabled: true    # log all requests by default
EOF
```

## Cleanup
```bash
gcloud container clusters delete mwy-llm-d --region us-central1
```
