# ShopKart with plain Kubernetes

This directory is the learning deployment. It uses ordinary Kubernetes YAML,
without Helm or Kustomize, so every object and relationship stays visible.
The existing Helm chart remains in `deploy/charts/` for the later templating
phase.

## What you are deploying

| Resource | Job in this project |
|---|---|
| Namespace | Isolates the dev environment |
| Secret | Supplies PostgreSQL credentials without committing them |
| StatefulSet and PVC | Run PostgreSQL with persistent local storage |
| Deployment | Maintains and rolls out each stateless API |
| Service | Gives each workload a stable DNS name and virtual IP |
| Startup, liveness, readiness probes | Separate slow startup, process health, and traffic readiness |
| HPA | Scales each API from CPU utilization |
| PDB | Protects critical APIs during voluntary disruptions |
| NetworkPolicy | Starts with default deny, then permits only required flows |
| CronJob | Retries failed notifications every ten minutes |
| Ingress | Routes `/api/products` and `/api/orders` into the cluster |

## 1. Install the local tools

Run these commands from PowerShell. Docker Desktop installation may require an
administrator prompt and a restart.

```powershell
winget install --exact --id Docker.DockerDesktop
winget install --exact --id Kubernetes.kubectl
winget install --exact --id Kubernetes.minikube
```

Start Docker Desktop, then verify the tools:

```powershell
docker version
kubectl version --client
minikube version
```

## 2. Create the cluster

Calico is selected so NetworkPolicy is enforced instead of silently ignored.
The metrics-server addon is required by the HPAs.

```powershell
minikube start --driver=docker --cpus=4 --memory=6144 --cni=calico
minikube addons enable ingress
minikube addons enable metrics-server
kubectl get nodes
```

## 3. Build the five application images

Run these commands from the `shopkart` directory. Building through Minikube
places the images where its container runtime can use them.

```powershell
$services = @(
  "catalog-service",
  "inventory-service",
  "payment-service",
  "notification-service",
  "order-service"
)

foreach ($service in $services) {
  minikube image build --tag "shopkart/${service}:dev" ".\services\${service}"
}

minikube image ls | Select-String "shopkart/"
```

## 4. Create the namespace and database Secret

The password is entered locally and is never written to Git. Use letters and
numbers only for this local exercise so it is safe inside the connection URL.

```powershell
kubectl apply -f .\deploy\kubernetes\dev\00-namespace.yaml

$dbPassword = Read-Host "Enter a local alphanumeric PostgreSQL password"
if ($dbPassword -notmatch '^[A-Za-z0-9]+$') {
  throw "Use only letters and numbers for this local password"
}

kubectl create secret generic shopkart-db `
  --namespace shopkart-dev `
  --from-literal="POSTGRES_USER=shopkart" `
  --from-literal="POSTGRES_PASSWORD=${dbPassword}" `
  --from-literal="POSTGRES_DB=shopkart" `
  --from-literal="SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/shopkart" `
  --from-literal="SPRING_DATASOURCE_USERNAME=shopkart" `
  --from-literal="SPRING_DATASOURCE_PASSWORD=${dbPassword}" `
  --dry-run=client -o yaml | kubectl apply -f -

Remove-Variable dbPassword

kubectl apply --dry-run=server -f .\deploy\kubernetes\dev
```

The Secret is intentionally not represented by a YAML file. Base64 is
encoding, not encryption.

## 5. Apply in dependency order

Start PostgreSQL first and wait for its readiness probe. The APIs can then
create their own tables and become Ready.

```powershell
kubectl apply -f .\deploy\kubernetes\dev\01-postgres.yaml
kubectl rollout status statefulset/postgres -n shopkart-dev --timeout=180s

kubectl apply -f .\deploy\kubernetes\dev\catalog-service.yaml
kubectl apply -f .\deploy\kubernetes\dev\inventory-service.yaml
kubectl apply -f .\deploy\kubernetes\dev\payment-service.yaml
kubectl apply -f .\deploy\kubernetes\dev\notification-service.yaml
kubectl apply -f .\deploy\kubernetes\dev\order-service.yaml
kubectl apply -f .\deploy\kubernetes\dev\notification-retry-cronjob.yaml
kubectl apply -f .\deploy\kubernetes\dev\ingress.yaml

kubectl wait --for=condition=Available deployment --all `
  --namespace shopkart-dev --timeout=180s
```

## 6. Observe before testing

Do not stop at `Running`. Confirm readiness, stable Service selectors, rollout
state, and HPA metrics.

```powershell
kubectl get pods,services,deployments,statefulsets,hpa,pdb,ingress -n shopkart-dev
kubectl get endpointslices -n shopkart-dev
kubectl get networkpolicies -n shopkart-dev
kubectl top pods -n shopkart-dev
```

Expected state:

- PostgreSQL has one Ready Pod.
- Each API Deployment has two Ready Pods after its HPA reconciles.
- Every API Service has EndpointSlices populated with Pod IPs.
- HPA targets may show `<unknown>` briefly while metrics-server collects data.

## 7. Prove the checkout flow

Keep each port-forward running in its own PowerShell terminal:

```powershell
kubectl port-forward service/ingress-nginx-controller 8080:80 -n ingress-nginx
```

```powershell
kubectl port-forward service/inventory-service 8002:80 -n shopkart-dev
```

From a third terminal, create a product through Ingress and seed its internal
inventory API:

```powershell
$product = @{
  sku = "TSHIRT-001"
  name = "Cotton Round Neck T-Shirt"
  description = "Regular fit, 100% cotton"
  category = "clothing"
  brand = "Nova"
  price = "799.00"
} | ConvertTo-Json

Invoke-RestMethod -Method Post `
  -Uri http://localhost:8080/api/products `
  -ContentType application/json -Body $product

$stock = @{sku = "TSHIRT-001"; quantity = 10} | ConvertTo-Json
Invoke-RestMethod -Method Post `
  -Uri http://localhost:8002/inventory `
  -ContentType application/json -Body $stock
```

Place an order through Ingress:

```powershell
$order = @{
  customer_id = "cust-1"
  items = @(@{sku = "TSHIRT-001"; quantity = 2})
  card_token = "tok_ok"
  email = "buyer@example.com"
  phone = "+919876543210"
} | ConvertTo-Json -Depth 4

Invoke-RestMethod -Method Post `
  -Uri http://localhost:8080/api/orders `
  -Headers @{"Idempotency-Key" = "demo-order-0001"} `
  -ContentType application/json -Body $order

Invoke-RestMethod http://localhost:8002/inventory/TSHIRT-001
```

The order should be `CONFIRMED`, and inventory should change from 10 available
to 8. Submit the same order with the same idempotency key again; it must return
the original order without reducing stock a second time.

Test the CronJob without waiting ten minutes:

```powershell
kubectl delete job notification-retry-manual -n shopkart-dev --ignore-not-found
kubectl create job --from=cronjob/notification-retry `
  notification-retry-manual -n shopkart-dev
kubectl wait --for=condition=Complete job/notification-retry-manual `
  -n shopkart-dev --timeout=120s
kubectl logs job/notification-retry-manual -n shopkart-dev
```

## Troubleshooting order

```powershell
kubectl get pods -n shopkart-dev
kubectl describe pod <pod-name> -n shopkart-dev
kubectl logs <pod-name> -n shopkart-dev
kubectl logs <pod-name> -n shopkart-dev --previous
kubectl get events -n shopkart-dev --sort-by=.lastTimestamp
kubectl describe hpa <service-name> -n shopkart-dev
```

Use the Pod status to choose the next check:

| Symptom | First thing to verify |
|---|---|
| `ErrImageNeverPull` | The five images exist in `minikube image ls` |
| `CreateContainerConfigError` | The `shopkart-db` Secret exists |
| Pod is Running but `0/1` Ready | `/readyz`, PostgreSQL, and application logs |
| HPA shows `<unknown>` | metrics-server and CPU requests |
| Service times out | EndpointSlice selectors, DNS, then NetworkPolicy |
| Ingress returns 404 | ingress addon, Ingress rules, and rewrite annotation |

## Cleanup

```powershell
kubectl delete namespace shopkart-dev
minikube stop
```

Use `minikube delete` when you also want to remove the cluster and its local
PostgreSQL volume.

## Why Helm comes next

Read the five service files side by side after this deployment works. Most of
their YAML is repeated; only names, images, resources, environment variables,
HPA targets, and network allow-lists differ. Helm will later move the repeated
shape into one template and keep only those differences in values files. That
way you will understand what Helm renders instead of treating the chart as a
black box.