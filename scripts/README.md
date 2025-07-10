# LLM-D on GKE Deployment Scripts

This directory contains scripts to automate the deployment of LLM-D on Google Kubernetes Engine.

## Directory Structure

```
scripts/
├── README.md                 # This file
├── deploy-all.sh            # Main orchestration script
├── setup-env.sh             # Environment setup and validation
├── install-deps.sh          # Install dependencies and repositories
├── create-cluster.sh        # Create GKE cluster and GPU nodepool
├── setup-k8s.sh             # Configure Kubernetes resources
├── deploy-llm-d.sh          # Deploy LLM-D components
├── configure-model.sh       # Configure ModelService for GKE
├── test-deployment.sh       # Test the deployment
├── cleanup.sh               # Clean up resources
├── config/
│   ├── llm-d-gke.yaml      # LLM-D core configuration
│   └── llm-d-sample.yaml   # Sample application configuration
└── utils/                   # Utility scripts (for future use)
```

## Quick Start

1. **Complete deployment** (runs all steps):
   ```bash
   ./scripts/deploy-all.sh
   ```

2. **Step-by-step deployment**:
   ```bash
   # 1. Setup environment
   ./scripts/setup-env.sh
   
   # 2. Install dependencies
   ./scripts/install-deps.sh
   
   # 3. Create GKE cluster
   ./scripts/create-cluster.sh
   
   # 4. Setup Kubernetes
   ./scripts/setup-k8s.sh
   
   # 5. Deploy LLM-D
   ./scripts/deploy-llm-d.sh
   
   # 6. Configure model service
   ./scripts/configure-model.sh
   
   # 7. Test deployment
   ./scripts/test-deployment.sh
   ```

## Prerequisites

Before running the scripts, ensure you have:

- **Google Cloud SDK** (gcloud) installed and authenticated
- **kubectl** installed
- **Helm** installed
- **Hugging Face account** with access to meta-llama/Llama-3.2-1B-Instruct model

## Environment Configuration

The scripts use a `.env` file for configuration. Run `./scripts/setup-env.sh` to create one with default values:

```bash
# Key variables you need to customize:
PROJECT_ID="your-gcp-project-id"
HF_TOKEN="your-huggingface-token"
CLUSTER_NAME="your-cluster-name"
REGION="us-central1"
```

## Script Details

### setup-env.sh
- Creates `.env` file with default values
- Validates environment variables
- Checks gcloud authentication
- Sets up project configuration

### install-deps.sh
- Validates CLI tool installation
- Clones llm-d-deployer repository
- Adds required Helm repositories
- Installs dependencies

### create-cluster.sh
- Creates GKE cluster with optimal settings
- Creates GPU nodepool with L4 GPUs
- Configures cluster credentials
- Enables necessary APIs and features

### setup-k8s.sh
- Creates Hugging Face token secret
- Installs Gateway API CRDs
- Sets up RBAC for metrics collection
- Configures cluster-level resources

### deploy-llm-d.sh
- Deploys LLM-D core components
- Deploys sample application
- Waits for components to be ready
- Shows deployment status

### configure-model.sh
- Fixes PATH and LD_LIBRARY_PATH for GKE
- Applies L4 GPU optimizations
- Configures memory and model settings
- Restarts services with new configuration

### test-deployment.sh
- Tests direct pod access
- Tests gateway access
- Provides external testing commands
- Validates deployment functionality

### cleanup.sh
- Interactive cleanup options
- Removes Kubernetes resources
- Optionally deletes GKE cluster
- Cleans up local files

## Usage Examples

### Testing the deployment
```bash
# Test within cluster
./scripts/test-deployment.sh

# Test external access
./scripts/test-deployment.sh external
```

### Cleanup options
```bash
# Interactive cleanup
./scripts/cleanup.sh

# Clean up Kubernetes resources only
./scripts/cleanup.sh k8s

# Delete entire cluster
./scripts/cleanup.sh cluster

# Clean up local files only
./scripts/cleanup.sh local

# Complete cleanup
./scripts/cleanup.sh all
```

### Manual testing
```bash
# Get external IP
kubectl get gateway llama-3-2-1b-instruct-gateway -o jsonpath='{.status.addresses[0].value}'

# Test with curl
curl -X POST http://EXTERNAL_IP:80/v1/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -d '{"model": "llama-3-2-1b-instruct", "prompt": "Hello", "max_tokens": 16}'
```

## Monitoring and Troubleshooting

### Check deployment status
```bash
kubectl get pods -l app.kubernetes.io/name=llama-3-2-1b-instruct
kubectl get modelservices
kubectl get gateways
```

### View logs
```bash
kubectl logs -l app.kubernetes.io/name=llama-3-2-1b-instruct -f
```

### Common issues
- **OOM errors**: Reduce `--max-model-len` in configure-model.sh
- **GPU not found**: Check nodepool has GPU nodes
- **Token issues**: Verify HF_TOKEN in .env file
- **Network issues**: Check firewall and VPC settings

## Customization

### Using different models
Edit `.env` file:
```bash
MODEL_ID="different-model/name"
MODEL_NAME="different-model-name"
```

### Adjusting GPU settings
Edit `create-cluster.sh`:
```bash
GPU_TYPE="nvidia-t4"  # or nvidia-v100, etc.
GPU_COUNT=2           # number of GPUs per node
```

### Modifying cluster size
Edit `.env` file:
```bash
MIN_NODES=0
MAX_NODES=10
INITIAL_NODES=2
```

## Security Notes

- Never commit `.env` files to version control
- Use least-privilege IAM roles
- Enable cluster security features (Workload Identity, etc.)
- Regularly update dependencies and container images

## Support

For issues:
1. Check the logs: `kubectl logs -l app.kubernetes.io/name=llm-d`
2. Verify cluster status: `kubectl get nodes`
3. Check the original README.md for detailed explanations
4. Review GKE and LLM-D documentation