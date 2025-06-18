# Deploying a Large Language Model with llm-d on Google Kubernetes Engine (GKE)
This guide provides step-by-step instructions for deploying a large language model using the `llm-d` architecture on a GKE cluster with GPU acceleration

## 1. Prerequisites
Before you begin, ensure you have the following:
* Google Cloud SDK (gcloud): Installed and authenticated.
* kubectl: The Kubernetes command-line tool.
* Helm: The package manager for Kubernetes.
* Hugging Face Account: You will need an account and an access token.
* Model Access: Request access to the meta-llama/Llama-3.2-1B-Instruct model on Hugging Face.

## 2. Environment Configuration
First, set up the environment variables that will be used throughout the deployment process.
```bash
# --- Google Cloud Platform Settings ---
export PROJECT_ID="gpu-launchpad-playground"
export REGION="us-central1"

# --- GKE Cluster Settings ---
export CLUSTER_NAME="mwy-llm-d"

# --- GKE Node Pool Settings ---
export NODE_LOCATIONS="us-central1-a,us-central1-b,us-central1-c"
export NODEPOOL_NAME="mwy-llm-d-l4"
export MACHINE_TYPE="g2-standard-8"
export GPU_TYPE="nvidia-l4"
export GPU_COUNT=1 # Number of GPUs to attach per VM
export GPU_DRIVER_VERSION="latest" # Use "latest" or a specific version

# --- Nodepool Autoscaling Settings ---
export MIN_NODES=0
export MAX_NODES=4
export INITIAL_NODES=1
```
Also set your huggingface token.
```bash
# --- Hugging Face Token ---
# Replace with your actual Hugging Face token
export HF_TOKEN="<INSERT YOUR TOKEN HERE>"
```

## 3. Infrastructure Setup
Next, create the GKE cluster and a dedicated GPU node pool.

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
### Create Hugging Face Token Secret ( Optional )
Create a Kubernetes secret to securely store your Hugging Face token. This will be used by `llm-d` to download the model.
You can skip this step if you're using the SampleApplication chart from the `llm-d-deployer` repo.
```bash
kubectl create secret generic llm-d-hf-token \
    --from-literal="HF_TOKEN=${HF_TOKEN}"
```


## Set up GKE Inference Gateway CRD and RBAC
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
This configuration enables the necessary backend services for `llm-d`, such as Redis and the model service.

```bash
cat <<'EOF' > llm-d-gke.yaml
sampleApplication:
  enabled: false
gateway:
  enabled: false	
redis:
  enabled: true
modelservice:
  vllm:
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

## 7. Deploy llm-d
Install the llm-d components using Helm and the configurations you just created.
```bash
helm install llm-d llm-d/llm-d -f llm-d-gke.yaml
helm install llm-d-sample llm-d/llm-d -f llm-d-sample.yaml 
```

## 8. Expose the Model with a Gateway
Create a Kubernetes Gateway and HTTPRoute to expose the deployed model to receive inference requests. This also includes health check and backend policies.
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
## 9. Model Service Adjustments
The `llm-d` image used by the default configuration does not work out of the box on GKE.
This can be fixed by adjusting the `PATH` and `LD_LIBRARY_PATH` variables in the `ModelService`

```bash
kubectl patch ModelService llama-3-2-3b-instruct --type='json' -p='[{"op": "add", "path": "/spec/decode/containers/0/env/-", "value": {"name": "PATH", "value": "/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/workspace/vllm/.vllm/bin:/root/.local/bin:/usr/local/ompi/bin"}}, {"op": "add", "path": "/spec/decode/containers/0/env/-", "value": {"name": "LD_LIBRARY_PATH", "value": "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/nixl/lib/x86_64-linux-gnu/:/usr/local/ompi/lib:/usr/lib:/usr/local/lib"}}]'

kubectl patch ModelService llama-3-2-3b-instruct --type='json' -p='[{"op": "add", "path": "/spec/prefill/containers/0/env/-", "value": {"name": "PATH", "value": "/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/workspace/vllm/.vllm/bin:/root/.local/bin:/usr/local/ompi/bin"}}, {"op": "add", "path": "/spec/prefill/containers/0/env/-", "value": {"name": "LD_LIBRARY_PATH", "value": "/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/nixl/lib/x86_64-linux-gnu/:/usr/local/ompi/lib:/usr/lib:/usr/local/lib"}}]'
```


### Optimize for the L4 GPU architecture ( Optional )
You may need to adjust the `ModelService` to optimize for the L4 GPU architecture.

To prevent out-of-memory errors, you can add arguments to the vllm startup command. For example, to set the GPU memory utilization:
```bash
# This is an example patch. The name of the ModelService might differ.
kubectl patch ModelService llama-3-2-1b-instruct --type='json' -p='[{"op": "add", "path": "/spec/decode/containers/0/args/-", "value": "--gpu-memory-utilization=0.95"}]'
```
Alternatively, you could reduce the maximum model length (context window):
```bash
# This is an example patch. The name of the ModelService might differ.
kubectl patch ModelService llama-3-2-1b-instruct --type='json' -p='[{"op": "add", "path": "/spec/decode/containers/0/args/-", "value": "--max-model-len=65536"}]'
```



## 10. Testing the Deployment
Once the deployment is complete, you can test it by sending a completion request.

### Using the included test script
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

### Manual testing
This will only work from the same region.
```bash
IP=$(kubectl get gateway/llama-3-2-1b-instruct-gateway -o jsonpath='{.status.addresses[0].value}')
PORT=80 # Use 80 for HTTP

curl -i -X POST ${IP}:${PORT}/v1/completions \
-H 'Content-Type: application/json' \
-H 'Authorization: Bearer $(gcloud auth print-access-token)' \
-d '{
    "model": "llama-3.2-1B-Instruct",
    "prompt": "Say something",
    "max_tokens": 8124,
    "temperature": "0.5"
}'
```

## 11. Cleanup
To remove all the resources created in this guide, delete the GKE cluster.
```bash
gcloud container clusters delete "$CLUSTER_NAME" --region "$REGION"
```



## Add another ModelService
This is full example how to add another ModelService
```yaml
kubectl apply -f - <<EOF
apiVersion: llm-d.ai/v1alpha1
kind: ModelService
metadata:
  name: qwen3-0-6b
spec:
  modelArtifacts:
    uri: hf://Qwen/Qwen3-0.6B
  decoupleScaling: false
  baseConfigMapRef:
    name: basic-gpu-preset
  routing:
    modelName: Qwen3-0.6B
  decode:
    replicas: 1
    containers:
    - name: "vllm"
      args:
      - "--model"
      - "Qwen/Qwen3-0.6B"
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
      - "Qwen/Qwen3-0.6B"
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
kind: Gateway
metadata:
  name: qwen3-0-6b-gateway
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
  name: qwen3-0-6b-route
spec:
  parentRefs:
  - name: qwen3-0-6b-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: qwen3-0-6b-inference-pool
      group: inference.networking.x-k8s.io
      kind: InferencePool
---
apiVersion: networking.gke.io/v1
kind: GCPBackendPolicy
metadata:
  name: qwen3-0-6b-backend-policy
  namespace: default
spec:
  default:
    logging:
      enabled: true
    timeoutSec: 300
  targetRef:
    group: inference.networking.x-k8s.io
    kind: InferencePool
    name: qwen3-0-6b-inference-pool
---
kind: HealthCheckPolicy
apiVersion: networking.gke.io/v1
metadata:
  name: qwen3-0-6b-health-check-policy
  namespace: default
spec:
  targetRef:
    group: "inference.networking.x-k8s.io"
    kind: InferencePool
    name: qwen3-0-6b-inference-pool
  default:
    config:
      type: HTTP
      httpHealthCheck:
          requestPath: /health
          port: 8000
EOF
```

## TODO
* GMP Monitoring
* Helm integration for HealthCheckPolicy, Gateway, GCPBackendPolicy, HTTPRoute
