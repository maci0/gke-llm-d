# gke-llm-d

## Create Cluster
```bash
gcloud beta container --project "gpu-launchpad-playground" clusters create "mwy-llm-d" --region "us-central1" --enable-dataplane-v2 --enable-dataplane-v2-metrics --enable-dataplane-v2-flow-observability --addons HorizontalPodAutoscaling,HttpLoadBalancing,NodeLocalDNS,GcePersistentDiskCsiDriver,GcsFuseCsiDriver --enable-autoupgrade --enable-autorepair --enable-managed-prometheus --workload-pool "gpu-launchpad-playground.svc.id.goog" --enable-shielded-nodes --shielded-integrity-monitoring --no-shielded-secure-boot
```
## Create GPU Nodepool
```bash
gcloud ........
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
