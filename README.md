# ShopKart Manifests

GitOps source of truth for the ShopKart deployment.

## Contents

- `deploy/charts/`: reusable Helm chart for all five services
- `deploy/envs/dev/`: development namespace, ingress, CronJob, and service values
- `deploy/argocd/`: AppProject, platform Application, and service ApplicationSet
- `deploy/kubernetes/`: raw Kubernetes learning manifests
- `monitoring/`: Prometheus rules, ServiceMonitor, Grafana dashboard, and stack values

Jenkins updates only the immutable image tag in the relevant values file. ArgoCD watches this repository and reconciles EKS; Jenkins never runs `kubectl` against the application cluster.

Validate one service release with:

```powershell
helm lint .\deploy\charts\shopkart-service -f .\deploy\envs\dev\values\catalog-service.yaml
helm template catalog-service .\deploy\charts\shopkart-service `
  -f .\deploy\envs\dev\values\catalog-service.yaml `
  --namespace shopkart-dev | kubeconform -strict -ignore-missing-schemas
```

Application source: https://github.com/saikrishna3709-shopkart/shopkart-platform
