# Benchmarking with inference-perf

This guide provides instructions for benchmarking the deployed Large Language Model (LLM) using the [`kubernetes-sigs/inference-perf`](https://github.com/kubernetes-sigs/inference-perf) toolkit.

We will use `uv` for fast Python package management and environment setup.

## 1. Prerequisites

- A deployed LLM on GKE as described in the `README.md`.
- The `MODEL_NAME` and `GATEWAY_IP` from your deployment.
- `uv` installed. If you don't have it, you can install it with:
  ```bash
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ```

## 2. Setup

### Clone the `inference-perf` Repository

First, clone the `inference-perf` repository to get the necessary benchmarking scripts.

```bash
git clone https://github.com/kubernetes-sigs/inference-perf.git
cd inference-perf
```

### Create Virtual Environment and Install Dependencies

Next, use `uv` to create a virtual environment and install the required Python packages.

```bash
# Create and activate a new virtual environment
uv venv

# Activate the environment
source .venv/bin/activate

# Install the inference-perf tool
uv pip install .
```

## 3. Running the Benchmark

### Create a Configuration File
The `inference-perf` tool uses a YAML configuration file to define the benchmark parameters. Create a file named `config.yml` with the following content:

```yaml
#config.yml

data:
  type: shareGPT
load:
  type: constant
  stages:
  - rate: 1
    duration: 30
api: 
  type: chat
server:
  type: vllm
  model_name: llama-3-2-1b-instruct
  base_url: http://<your-gateway-ip>
tokenizer:
  pretrained_model_name_or_path: HuggingFaceTB/SmolLM2-135M-Instruct
```

**Important:** Replace `<your-gateway-ip>` with the actual IP address of your gateway. You can get it by running:

```bash
export MODEL_NAME="llama-3-2-1b-instruct"
kubectl get gateway/${MODEL_NAME}-gateway -o jsonpath='{.status.addresses[0].value}'
```

### Execute the Benchmark

Now you can run the `inference-perf` command with your configuration file:

```bash
export HF_TOKEN=<your token>
inference-perf --config_file config.yml
```

### Understanding the Output

The benchmark results will be saved to the path specified in your `config.yml` file (in this case, `/tmp/results.json`). The output file contains detailed metrics, including:

- **Throughput**: The number of output tokens per second.
- **Latency**: The time taken to generate each token (time per output token).
- **TTFT**: Time To First Token.

You can analyze this JSON file to understand the performance characteristics of your LLM deployment.
