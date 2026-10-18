# ShopKart Manifests

GitOps source of truth for the ShopKart deployment.

## Contents

- `deploy/charts/`: reusable Helm chart for all six services
- `deploy/envs/dev/`: development namespace, ALB ingress, AWS secret store,
  CronJob, and service values
- `deploy/argocd/`: AppProject, platform Application, and service ApplicationSet
- `deploy/kubernetes/`: raw Kubernetes learning manifests
- `monitoring/`: Prometheus rules, ServiceMonitor, Grafana dashboard, and stack values

Jenkins updates the immutable image tag and repository path in the relevant
values file. ArgoCD watches this repository and reconciles EKS; the delivery
pipeline never runs `kubectl` against the application cluster.

## Substitution Tokens

Nothing here is tied to one AWS account or one GitHub owner, so two tokens must
be replaced at apply time. They are deliberately not committed:

| Token | Replace with | Where |
| --- | --- | --- |
| `__ECR_REGISTRY__` | `<account-id>.dkr.ecr.<region>.amazonaws.com` | `deploy/argocd/shopkart-dev.yaml` |
| `__MANIFESTS_REPO_URL__` | the HTTPS URL of **your** fork of this repository | `deploy/argocd/shopkart-dev.yaml` |

```bash
sed -e "s|__ECR_REGISTRY__|${ECR_REGISTRY}|g" \
    -e "s|__MANIFESTS_REPO_URL__|${MANIFESTS_REPO_URL}|g" \
    deploy/argocd/shopkart-dev.yaml | kubectl apply -f -
```

Applying the file without substituting leaves ArgoCD pointing at a repository
named `__MANIFESTS_REPO_URL__` and every pod in `ImagePullBackOff`. The
`image.registry` value is injected by the ApplicationSet, so per-service values
files carry only `shopkart/<service>` and never an account ID.

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

## Development Database Connections

Each of the five database-backed services uses a maximum of two Hikari
connections per pod and keeps one idle connection. At the initial two replicas
per service this budgets 20 connections, instead of 150. The configured HPA
ceilings plus one surge pod per service can use up to 70 connections; reserve
additional database capacity for administration and other consumers.

These dev services allow one unavailable replica during rolling updates. This
lets old pods release their connection pools without waiting for replacement
pods to obtain a database connection first. With two healthy replicas, one can
remain available during replacement. This availability tradeoff is specific
to the small shared development database, not a production rollout default.
ArgoCD applies these settings without rebuilding the application images.

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
