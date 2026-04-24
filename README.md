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

Loki deployed as a separate components Loki in SingleBinary with filesystem and Promtail. This setup is non-production.
https://grafana.com/docs/loki/latest/setup/install/helm/install-monolithic/#single-replica

Login to Grafana and explore logs and check that Loki datasource is accessible:
```shell
http://grafana.local/
```

## 7. Bank Vault Operator (example with local vault file unsealer)

https://bank-vaults.dev/docs/installing/
Inspired by this [demo](https://github.com/sagikazarmark/demo-bank-vaults/tree/main)

### Components and version chain

Three independent pieces make up the stack:

| Component | Source | Role |
|---|---|---|
| `vault-operator` | Helm chart | Kubernetes operator. Watches the `Vault` CR and reconciles the Vault StatefulSet + Configurer Job. |
| `vault-secrets-webhook` | Helm chart | Mutating admission webhook. Injects a secret-fetch sidecar into pods annotated with `vault.security.banzaicloud.io/*`. Independent of the operator — works on its own. |
| `Vault` CR | Manifest | Declarative spec of the Vault cluster itself. Read by the operator. |

The `Vault` CR pins 2 container images:

- `image: hashicorp/vault` — upstream HashiCorp Vault server. Independent release cycle.
- `bankVaultsImage: bank-vaults/bank-vaults` — the bank-vaults CLI. Runs as sidecar in each Vault pod and as the Configurer Job. Handles init/unseal (keys stored in a K8s Secret) and applies everything under `externalConfig:` (policies, auth methods, secrets engines, `startupSecrets`) through the Vault API.

### Important considerations

- This setup is non-production, becase unseal keys are stored in the same cluster and k8s secrets, consider KMS
- The unseal keys and root token are managed by the Bank-Vaults operator.
- There are 5 key shares created, with a threshold of 3 required to unseal Vault.
- The unseal information is stored as Kubernetes Secrets in the "vault" namespace.
- The secrets managed by Vault are stored in the Raft storage, which is persisted on the Kubernetes PersistentVolumes.
- Each Vault pod will have its own PersistentVolume, and Raft ensures that the data is replicated across these volumes for high availability.


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

## Moving applications to ArgoCD pattern

1. Drop the chart's values into `argocd/helm-values/<app>/values.yaml`.
2. Write an `Application` (static values) or `ApplicationSet` (needs cluster Secret annotations) YAML in `argocd/applications/apps/<app>.yaml` or `argocd/applications/core/<app>.yaml`.
3. Push to the repo — ArgoCD picks it up automatically


## Hipster demo app without Istio (bank-vaults injection demo)

Managed by the [hipster ApplicationSet](argocd/applications/apps/hipster.yaml); manifests live in [argocd/manifests/hipster/](argocd/manifests/hipster/). UI at http://hipster.local/ once Synced.

Each service demonstrates one secret-injection pattern. The Hipster app code itself
doesn't consume these values — they're only there so the webhook has something to
mutate and you can verify by exec-ing into the pod.

| Service | Pattern | Where it's wired |
|---|---|---|
| currencyservice | Inline env: `value: vault:secret/...#KEY` | [currencyservice.yaml](argocd/manifests/hipster/currencyservice.yaml) |
| paymentservice | Secret with `vault:` refs → `secretKeyRef` | [paymentservice.yaml](argocd/manifests/hipster/paymentservice.yaml) (Deployment + `demo-payment-credentials` Secret) |
| emailservice | ConfigMap with `vault:` refs → `envFrom` | [emailservice.yaml](argocd/manifests/hipster/emailservice.yaml) (Deployment + `demo-smtp-config` ConfigMap) |
| cartservice | KV-v2 version pinning: `vault:...#KEY#1` | [cartservice.yaml](argocd/manifests/hipster/cartservice.yaml) |
| adservice | PKI cert on disk via `consul-template` sidecar | [adservice.yaml](argocd/manifests/hipster/adservice.yaml) (Deployment + `demo-pki-ct-config` ConfigMap) |

You can retreive secrets inside the POD via command: `/vault/vault-env env`

Verify resolved secrets values:

```bash
# Pattern 1 — inline env resolved by vault-env at container start (currencyservice):
k -n hipster exec deploy/currencyservice -- /vault/vault-env env | grep AWS_

# Pattern 2 — Secret with mutate: "skip"; real value stays as a `vault:...` placeholder in
# etcd, and vault-env resolves it in the paymentservice process at runtime.
k -n hipster get secret demo-payment-credentials -o jsonpath='{.data.stripe-api-key}' | base64 -d; echo
# Expect the literal string: vault:secret/data/payment#STRIPE_API_KEY
k -n hipster exec deploy/paymentservice -- /vault/vault-env env | grep STRIPE_API_KEY
# Expect the resolved value: sk_test_demoStripeKey

# Pattern 3 — ConfigMap without mutate: "skip"; the webhook rewrites the CM at admission,
# so etcd stores real values and the pod can read them with a plain `env` (no vault-env needed).
k -n hipster get cm demo-smtp-config -o jsonpath='{.data.SMTP_PASSWORD}'; echo
# Expect the real value: s3cr3t-smtp-pw
k -n hipster exec deploy/emailservice -- env | grep SMTP_

# Pattern 4 — KV-v2 version pin (cartservice). Pod always reads v1:
k -n hipster exec deploy/cartservice -- /vault/vault-env env | grep MYSQL_PASSWORD
# Write a newer version and restart — pod still sees the v1 value because the ref is pinned:
vault kv put secret/mysql MYSQL_PASSWORD=changed-in-v2 MYSQL_ROOT_PASSWORD=s3cr3t
k -n hipster rollout restart deploy/cartservice
k -n hipster exec deploy/cartservice -- /vault/vault-env env | grep MYSQL_PASSWORD

# Pattern 5 — PKI cert written to disk by consul-template sidecar (adservice):
kubectl -n hipster exec deploy/adservice -c server -- ls /vault/secrets/
kubectl -n hipster exec deploy/adservice -c server -- \
  sh -c 'openssl x509 -in /vault/secrets/server.crt -noout -subject -issuer -dates'
```
