# ShopKart Manifests

GitOps source of truth for the ShopKart deployment.

## Contents

- `deploy/charts/`: reusable Helm chart for all six services
- `deploy/envs/dev/`: development namespace, ALB ingress, AWS secret store,
  CronJob, and service values
- `deploy/argocd/`: AppProject, platform Application, and service ApplicationSet
- `deploy/kubernetes/`: raw Kubernetes learning manifests
- `monitoring/`: Prometheus rules, ServiceMonitor, Grafana dashboard, and stack values

Jenkins updates the account-specific ECR repository and immutable image tag in
the relevant values file. ArgoCD watches this repository and reconciles EKS;
Jenkins never runs `kubectl` against the application cluster.

Validate one service release with:

```powershell
helm lint .\deploy\charts\shopkart-service -f .\deploy\envs\dev\values\catalog-service.yaml
helm template catalog-service .\deploy\charts\shopkart-service `
  -f .\deploy\envs\dev\values\catalog-service.yaml `
  --namespace shopkart-dev | kubeconform -strict -ignore-missing-schemas
```

## Demo Validation

From the sibling `shopkart-platform` checkout on Windows:

```powershell
.\ci\scripts\demo.ps1 -Action validate
```

This checks all six ApplicationSet names and values paths, renders the actual
service chart, parses the shared pipeline, and checks the rendered monitoring
configuration. Java 21, Maven, Helm, and all three sibling checkouts are required.
The monitoring chart may be downloaded; no cluster or AWS account is contacted.

## Short-Lived Monitoring

After the AWS environment has been approved and provisioned, run from this
repository in an authenticated administration terminal:

```bash
helm upgrade --install kube-prometheus-stack kube-prometheus-stack --repo https://prometheus-community.github.io/helm-charts --version 82.2.0 --namespace monitoring --create-namespace --wait --timeout 10m -f monitoring/kube-prometheus-stack-values.yaml
kubectl apply -f monitoring/servicemonitor.yaml -f monitoring/alerts.yaml -f monitoring/grafana-dashboard.yaml
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

The demo stores metrics and dashboards on ephemeral storage and needs no `gp3`
StorageClass or EBS CSI driver. Grafana's chart generates its admin password in
a Kubernetes Secret. Alertmanager records alerts without external notifications;
Slack and PagerDuty integrations are intentionally not configured. Data is lost
when the relevant pods are replaced. Do not use these values as production defaults.

Application source: https://github.com/saikrishna3709-shopkart/shopkart-platform
