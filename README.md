# Infra Components

AWS EKS layer (Terraform):
- [x] VPC
- [x] EKS cluster and EKS addons
- [x] Karpenter
- [x] AWS Load Balancer Controller IAM
- [x] ArgoCD
- [x] GitOps Bridge — cluster Secret + root Application

Core layer (ArgoCD at `argocd/applications/core/`):
- [x] Traefik ingress controller
- [x] AWS Load Balancer Controller (Helm release; IAM stays in TF)
- [x] Kube-Prometheus-Stack — metrics
- [x] Grafana Loki + Promtail — logging
- [x] Hashicorp Vault + Bank Vaults Operator — secrets management
- [ ] Trivy Operator — security
- [ ] Kyverno — policy
- [ ] Grafana Tempo — tracing

Applications layer (ArgoCD at `argocd/applications/apps/`):
- [ ] Demo App — for Vault secret injection demo
- [ ] Hipster App — Demo app without Istio


## Deployment

1. Terraform — creates VPC, EKS, Karpenter, ArgoCD, cluster Secret, root Application.
2. ArgoCD picks up the root Application → recursively discovers `argocd/applications/core/` and `argocd/applications/apps/`.
3. ApplicationSets materialise child Applications that install Traefik, ALB controller, etc.
4. Traefik comes up, NLB gets provisioned by ALB controller, you map the NLB IP in `/etc/hosts`.

### 1. Terraform

```shell
cd terraform
terraform init -upgrade
terraform apply
```

### 2. Wait for ArgoCD to sync core platform

During the first minutesthe ArgoCD UI is not yet reachable via `argocd.local`. 
Access the UI via port-forward:

```shell
kubectl -n argocd port-forward svc/argocd-server 8080:80
# open http://localhost:8080
```

### 3. Map the NLB IP into `/etc/hosts`

```shell
kubectl -n traefik get svc traefik \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
  | xargs dig +short
```

Pick any one of the returned IPs and add:

```shell
<IP>  argocd.local vault.local hipster.local grafana.local prometheus.local alertmanager.local
```

### 4. Retrieve ArgoCD admin password

```shell
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

Login to CLI and add the GitOps repo (if not public):

```shell
argocd login argocd.local:443

argocd repo add https://github.com/silazare/argocd-infra-example.git \
  --username silazare --password github_pat_xxxxx

argocd repo add ghcr.io --type helm --name stable --enable-oci
```

## 5. Kube-prometheus-stack admin password

```shell
k -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

Login to Grafana:
```shell
http://grafana.local/
```

## 6. Grafana Loki

Loki deployed as a separate components Loki in SingleBinary with filesystem and Promtail.
https://grafana.com/docs/loki/latest/setup/install/helm/install-monolithic/#single-replica

Login to Grafana and explore logs and check that Loki datasource is accessible:
```shell
http://grafana.local/
```

## 7. Bank-vaults (demo example with local vault file unsealer)

Inspired by this [demo](https://github.com/sagikazarmark/demo-bank-vaults/tree/main)

Wait until Vault will be synced

Login to Vault UI and retreive root token:
```shell
k -n vault get secret vault-unseal-keys -o jsonpath="{.data.vault-root}" | base64 -d
```

Login to Vault CLI:
```shell
export VAULT_ADDR=http://vault.local
export VAULT_SKIP_VERIFY=true
vault status

export VAULT_TOKEN="xxxxx"
vault kv get secret/mysql
vault kv get secret/accounts/aws
```

Deploy demo application and check webhook logs and application POD:

You can retreive secrets inside the container via command: `/vault/vault-env env`

## Moving applications to ArgoCD pattern

1. Drop the chart's values into `argocd/helm-values/<app>/values.yaml`.
2. Write an `Application` (static values) or `ApplicationSet` (needs cluster Secret annotations) YAML in `argocd/applications/apps/<app>.yaml` or `argocd/applications/core/<app>.yaml`.
3. Push to the repo — ArgoCD picks it up automatically


## Hipster demo app deploy (without Istio)

1) Create Hipster application:
```
k apply -f hipster-app/application.yaml
```

2) Wait until app will be synced

3) Login to Frontend UI and make sure app is working fine:
```
http://hipster.local/
```
