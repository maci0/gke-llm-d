# Deploying a Large Language Model with llm-d on Google Kubernetes Engine (GKE)
This guide provides step-by-step instructions for deploying a large language model using the `llm-d` architecture on a GKE cluster with GPU acceleration

## 1. Prerequisites
Before you begin, ensure you have the following:
* Google Cloud SDK (gcloud): Installed and authenticated.
* kubectl: The Kubernetes command-line tool.
* Helm: The package manager for Kubernetes.
* Hugging Face Account: You will need an account and an access token.
* Model Access: Request access to the meta-llama/Llama-3.2-8B-Instruct model on Hugging Face.

## 2. Environment Configuration
First, set up the environment variables that will be used throughout the deployment process.
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

helm repo update
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
  vllm:
    enabled: true
    #image:
      #registry: registry.hub.docker.com
      #repository: vllm/vllm-openai
      #tag: v0.9.1
EOF

```

## configure llm-d sample app
```bash
cat <<'EOF' > llm-d-sample.yaml
sampleApplication:
  enabled: true
  baseConfigMapRefName: basic-gpu-preset
  model:
    modelArtifactURI: hf://meta-llama/Llama-3.2-1B-Instruct
    modelName: "llama-3.2-1B-Instruct"
gateway:
  enabled: false
modelservice:
  enabled: false
redis:
  enabled: false
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
helm install llm-d-sample llm-d/llm-d -f llm-d-sample.yaml 

```

## Create gateway and route
```yaml
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: llama-3-2-1b-instruct-gateway
spec:
  gatewayClassName: gke-l7-rilb
  listeners:
    - protocol: HTTP # Or HTTPS for production
      port: 80 # Or 443 for HTTPS
      name: http
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: llama-3-2-1b-instruct-route
spec:
  parentRefs:
  - name: llama-3-2-1b-instruct-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: llama-3-2-1b-instruct-inference-pool
      group: inference.networking.x-k8s.io
      kind: InferencePool
---
apiVersion: networking.gke.io/v1
kind: GCPBackendPolicy
metadata:
  name: llama-3-2-1b-instruct-backend-policy
  namespace: default
spec:
  default:
    logging:
      enabled: true
    timeoutSec: 300
  targetRef:
    group: inference.networking.x-k8s.io
    kind: InferencePool
    name: llama-3-2-1b-instruct-inference-pool
---
kind: HealthCheckPolicy
apiVersion: networking.gke.io/v1
metadata:
  name: llama-3-2-1b-instruct-health-check-policy
  namespace: default
spec:
  targetRef:
    group: "inference.networking.x-k8s.io"
    kind: InferencePool
    name: llama-3-2-1b-instruct-inference-pool
  default:
    config:
      type: HTTP
      httpHealthCheck:
          requestPath: /health
          port: 8000
EOF
```


## fix PATH and LD_LIBRARY_PATH
```bash
kubectl patch ModelService llama-3-2-3b-instruct --type='json' -p='[{"op": "add", "path": "/spec/decode/containers/0/env/-", "value": {"name": "PATH", "value": "/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/workspace/vllm/.vllm/bin:/root/.local/bin:/usr/local/ompi/bin"}}, {"op": "add", "path": "/spec/decode/containers/0/env/-", "value": {"name": "LD_LIBRARY_PATH", "value": "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/nixl/lib/x86_64-linux-gnu/:/usr/local/ompi/lib:/usr/lib:/usr/local/lib"}}]'

kubectl patch ModelService llama-3-2-3b-instruct --type='json' -p='[{"op": "add", "path": "/spec/prefill/containers/0/env/-", "value": {"name": "PATH", "value": "/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/workspace/vllm/.vllm/bin:/root/.local/bin:/usr/local/ompi/bin"}}, {"op": "add", "path": "/spec/prefill/containers/0/env/-", "value": {"name": "LD_LIBRARY_PATH", "value": "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/nixl/lib/x86_64-linux-gnu/:/usr/local/ompi/lib:/usr/lib:/usr/local/lib"}}]'
```
## Notes
On L4 GPUs probably have to edit the ModelService and add `--gpu-memory-utilization 0.95` to vllm startup options or reduce the context window with like so `--max-model-len 65536`


## Testing
```bash
IP=$(kubectl get gateway/llama-3-2-3b-instruct-gateway -o jsonpath='{.status.addresses[0].value}')
PORT=80 # Use 80 for HTTP

curl -i -X POST ${IP}:${PORT}/v1/completions \
-H 'Content-Type: application/json' \
-H 'Authorization: Bearer $(gcloud auth print-access-token)' \
-d '{
    "model": "llama-3.2-3B-Instruct",
    "prompt": "Say something",
    "max_tokens": 8124,
    "temperature": "0.5"
}'
```

## Testing
More work to be done here:
```bash
./test-request.sh -n default
Namespace: default
Model ID:  none; will be discover from first entry in /v1/models

1 -> Fetching available models from the decode pod at 10.108.4.9…
{"object":"list","data":[{"id":"llama-3.2-3B-Instruct","object":"model","created":1750231376,"owned_by":"vllm","root":"meta-llama/Llama-3.2-3B-Instruct","parent":null,"max_model_len":65536,"permission":[{"id":"modelperm-f795474b454c41769e10dffd191ca203","object":"model_permission","created":1750231376,"allow_create_engine":false,"allow_sampling":true,"allow_logprobs":true,"allow_search_indices":false,"allow_view":true,"allow_fine_tuning":false,"organization":"*","group":null,"is_blocking":false}]}]}pod "curl-4912" deleted

Discovered model to use: llama-3.2-3B-Instruct

2 -> Sending a completion request to the decode pod at 10.108.4.9…
If you don't see a command prompt, try pressing enter.
{"id":"cmpl-4d3a726fbc734d1591b381fa08ff04ed","object":"text_completion","created":1750231379,"model":"llama-3.2-3B-Instruct","choices":[{"index":0,"text":" (The story of a young woman)\nI am a young woman, a daughter","logprobs":null,"finish_reason":"length","stop_reason":null,"prompt_logprobs":null}],"usage":{"prompt_tokens":5,"total_tokens":21,"completion_tokens":16,"prompt_tokens_details":null},"kv_transfer_params":null}pod "curl-9478" deleted

3 -> Fetching available models via the gateway at 10.128.0.171…
{"object":"list","data":[{"id":"llama-3.2-3B-Instruct","object":"model","created":1750231383,"owned_by":"vllm","root":"meta-llama/Llama-3.2-3B-Instruct","parent":null,"max_model_len":65536,"permission":[{"id":"modelperm-8944305d311344c38ad54c67310d70aa","object":"model_permission","created":1750231383,"allow_create_engine":false,"allow_sampling":true,"allow_logprobs":true,"allow_search_indices":false,"allow_view":true,"allow_fine_tuning":false,"organization":"*","group":null,"is_blocking":false}]}]}pod "curl-7984" deleted


4 -> Sending a completion request via the gateway at 10.128.0.171 with model 'llama-3.2-3B-Instruct'…
{"choices":[{"finish_reason":"length","index":0,"logprobs":null,"prompt_logprobs":null,"stop_reason":null,"text":" I am a user of the internet, a student, a curious individual with a"}],"created":1750231387,"id":"cmpl-12893c3c4c8e4518b552f9e47d5bff7b","kv_transfer_params":null,"model":"llama-3.2-3B-Instruct","object":"text_completion","usage":{"completion_tokens":16,"prompt_tokens":5,"prompt_tokens_details":null,"total_tokens":21}}pod "curl-2163" deleted

All tests complete.
```


## other ModelService
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
      args:
      - "--model"
      - "meta-llama/Llama-3.2-3B-Instruct"
      - "--max-model-len"
      - "65536"
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
EOF
```

# TODO

this stuff needs to be integrated better

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



## Cleanup
```bash
gcloud container clusters delete mwy-llm-d --region us-central1
```
