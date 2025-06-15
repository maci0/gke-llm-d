# gke-llm-d

## Create Cluster
```bash
gcloud beta container --project "gpu-launchpad-playground" clusters create "mwy-llm-d" --region "us-central1" --enable-dataplane-v2 --enable-dataplane-v2-metrics --enable-dataplane-v2-flow-observability --addons HorizontalPodAutoscaling,HttpLoadBalancing,NodeLocalDNS,GcePersistentDiskCsiDriver,GcsFuseCsiDriver --enable-autoupgrade --enable-autorepair --enable-managed-prometheus --workload-pool "gpu-launchpad-playground.svc.id.goog" --enable-shielded-nodes --shielded-integrity-monitoring --no-shielded-secure-boot
```

## Set up GKE Inference Gateway
