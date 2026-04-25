# Project Overview

AWS EKS cluster bootstrap with ArgoCD for GitOps, deployed via Terraform. Terraform provisions only the cluster-layer (VPC, EKS, Karpenter, IAM, ArgoCD, the GitOps bridge). Everything above the cluster layer — ingress controllers, apps — is managed by ArgoCD from this repo.

## Two-layer architecture

```
Terraform (cluster-layer — anything AWS-native or required for ArgoCD itself)
  ↓  cluster Secret (GitOps bridge)
  ↓  root Application
ArgoCD GitOps (platform + apps — everything that runs *on top of* the cluster)
```

**Boundary rule:** Terraform manages anything that requires AWS API or must exist for ArgoCD to run. ArgoCD manages everything else. Karpenter is deliberately on the Terraform side — it provisions *capacity* for the cluster (same layer as VPC-CNI / EBS-CSI), it's not an application.

## Repository layout

```
terraform/                        # cluster-layer
  main.tf                         # locals, region, shared data sources
  versions.tf                     # provider + Terraform version pins
  providers.tf                    # aws, helm, kubectl, kubernetes (all with exec auth)
  vpc.tf                          # VPC module + ingress SGs
  eks.tf                          # EKS module (addons incl. EBS CSI Pod Identity assoc) + Karpenter submodule
  karpenter.tf                    # Karpenter Helm CRD + chart + default NodePool/NodeClass
  iam.tf                          # Shared Pod Identity assume policy + EBS CSI role + ALB controller role/policy/assoc
  argocd.tf                       # ArgoCD Helm release + cluster Secret + root Application

argocd/applications/              # GitOps — discovered recursively by the root Application
  core/                           # platform-layer components
    traefik.yaml                  # ApplicationSet, reads traefik_sg_id from cluster Secret
    alb-controller.yaml           # ApplicationSet, reads vpc_id + cluster_name
    kube-prometheus-stack.yaml    # ApplicationSet, multi-source (chart + git $values)
    grafana-loki.yaml             # ApplicationSet, multi-source (loki + promtail charts + git $values)
    bank-vaults.yaml              # ApplicationSet, multi-source (operator + webhook charts + raw manifests + git $values)
    storage-classes.yaml          # ApplicationSet, raw manifests only
  apps/                           # workload-layer
    hipster.yaml                  # ApplicationSet, raw manifests only

argocd/helm-values/               # static Helm values pulled via multi-source $values ref
  traefik/values.yaml
  alb-controller/values.yaml
  kube-prometheus-stack/values.yaml
  grafana-loki/                   # one file per sub-chart
    loki-values.yaml
    promtail-values.yaml
  bank-vaults/
    vault-operator-values.yaml    # vault-secrets-webhook uses chart defaults

argocd/manifests/                 # raw k8s manifests referenced by ApplicationSets that don't install Helm
  bank-vaults/                    # Namespace + RBAC + Vault CR (externalConfig: policies, k8s-auth roles, PKI, startupSecrets)
  hipster/                        # per-service Deployments + inline demo Secret/ConfigMap for each bank-vaults injection pattern
  storage-classes/                # gp3 StorageClass (EBS CSI)

_archive/                         # retired manifests kept for reference (old imperative demo-app, pre-GitOps Vault CR)
```

## Upstream modules & references

- [terraform-aws-modules/vpc/aws](https://github.com/terraform-aws-modules/terraform-aws-vpc) — VPC
- [terraform-aws-modules/eks/aws](https://github.com/terraform-aws-modules/terraform-aws-eks) — EKS cluster + Karpenter submodule
- [argo-helm ArgoCD chart](https://github.com/argoproj/argo-helm) — ArgoCD bootstrap
- [GitOps Bridge pattern](https://github.com/gitops-bridge-dev/gitops-bridge) — the TF→ArgoCD contract we use
- [aws-ia/terraform-aws-eks-blueprints-addons](https://github.com/aws-ia/terraform-aws-eks-blueprints-addons) — reference for which addon parameters typically flow through cluster Secret annotations

## GitOps Bridge contract

Terraform writes a `kubernetes_secret` named `in-cluster` in the `argocd` namespace, labelled `argocd.argoproj.io/secret-type: cluster`. Its annotations carry per-cluster parameters:

| Annotation | Source | Consumed by |
|---|---|---|
| `cluster_name` | `module.eks.cluster_name` | alb-controller |
| `region` | `local.region` | alb-controller |
| `vpc_id` | `module.vpc.vpc_id` | alb-controller |
| `traefik_sg_id` | `aws_security_group.ingress_traefik_external.id` | traefik |
| `target_revision` | `local.argocd_target_revision` | every ApplicationSet (git ref of the `$values` source) |

IAM role ARNs are **not** published as annotations — Pod Identity associations (see [iam.tf](terraform/iam.tf) for ALB, [eks.tf](terraform/eks.tf) for the EBS CSI addon's inline `pod_identity_association`) wire SAs to IAM roles at the AWS API level, so Helm values never need the role ARN.

ApplicationSets in `argocd/applications/{core,apps}/` use a `clusters` generator that matches this Secret and expands `{{metadata.annotations.*}}` placeholders inline. Helm-based Applications pull their static values from `argocd/helm-values/<app>/...` via a multi-source `$values` ref. Pure-manifest Applications point at a directory under `argocd/manifests/<app>/` and apply every `.yaml` there.

## Component relationships

Terraform-layer:
- **VPC** → **EKS**: VPC id and private subnets. Traefik-specific SGs live in VPC so they're available for the cluster Secret.
- **EKS** → **Karpenter submodule**: cluster_name for IAM / SQS / EventBridge wiring.
- **EKS + Karpenter submodule** → **Karpenter Helm** (`karpenter.tf`): `queue_name` + `node_iam_role_name` as Helm values. EC2NodeClass carries `ebs.csi.aws.com/cluster-name` so Karpenter-provisioned nodes satisfy the EBS CSI scoped IAM policy; the managed NG in `eks.tf` carries the same tag.
- **EKS** → **ALB controller Pod Identity** (`iam.tf`): standalone `aws_eks_pod_identity_association` for `aws-load-balancer-controller` SA in `kube-system`.
- **EKS** → **EBS CSI Pod Identity** (`eks.tf`): inline `pod_identity_association` inside the `aws-ebs-csi-driver` addon block, referencing `aws_iam_role.ebs_csi_controller` from `iam.tf`.
- Both Pod Identity roles share a single assume policy (`data.aws_iam_policy_document.pod_identity_assume` in `iam.tf`) trusting `pods.eks.amazonaws.com`.
- **ArgoCD Helm release** → **cluster Secret** → **ApplicationSets**: the chain that lets Git manifests consume TF outputs.

GitOps-layer:
- **storage-classes** → provides `gp3` → consumed by any PVC in the cluster (e.g. `vault-raft-*` in the Vault StatefulSet). Kept as a standalone ApplicationSet so SC lifecycle isn't tied to any one workload.
- **bank-vaults** is a single ApplicationSet bundling four sources: vault-operator chart, vault-secrets-webhook chart, raw manifests (Namespace, RBAC, **Vault CR**), and a git `$values` ref. The Vault CR's `externalConfig` declares k8s-auth roles (`hipster`, `vault-secrets-webhook`), the PKI secrets engine, and `startupSecrets` seeded into the KV engine — re-applied by the Configurer Job on every CR change.
- **hipster** → **bank-vaults webhook**: pods/Secrets/ConfigMaps in the `hipster` namespace are annotated with `vault.security.banzaicloud.io/*`; the webhook resolves `vault:...` references at pod runtime via an injected vault-env binary (patterns 1–4) or via a consul-template + vault-agent sidecar pair reading PKI certs to disk (pattern 5).
- **kube-prometheus-stack** / **grafana-loki**: multi-source Applications — a chart source plus a git `$values` ref. Grafana ingress + Loki datasource are wired via values; no cluster-Secret annotations needed.

## Bank Vaults (secrets plane — critical)

The secrets subsystem. It's the load-bearing piece for everything in `hipster/` and anything else that eventually uses Vault.

### Sub-components

| Piece | Source | Role |
|---|---|---|
| `vault-operator` | Helm chart (bank-vaults OCI repo) | Reconciles the Vault StatefulSet + Configurer Job from the Vault CR. |
| `vault-secrets-webhook` | Helm chart (bank-vaults OCI repo) | Mutating admission webhook. Injects `vault-env` and, on annotated pods, `consul-template` + `vault-agent` sidecars. Independent of the operator. |
| `Vault` CR | raw manifest ([argocd/manifests/bank-vaults/vault-cr.yaml](argocd/manifests/bank-vaults/vault-cr.yaml)) | Declarative Vault cluster: image pins, Raft storage, unseal config, `externalConfig`. |

All three ship under a single multi-source ApplicationSet, [argocd/applications/core/bank-vaults.yaml](argocd/applications/core/bank-vaults.yaml). The `vault-operator` chart version and `bankVaultsImage` tag in the Vault CR come from the same upstream release and bump together; the webhook chart has its own cadence; `hashicorp/vault` server image is independent.

### Vault CR — what `externalConfig` wires

- **Policies**: `allow_secrets` (full CRUD on `secret/*`), `allow_pki` (full CRUD on `pki/*`).
- **Kubernetes auth roles**:
  - `default` / `demo` / `hipster` — bound to SAs in same-named namespaces. `hipster` gets both `allow_secrets` and `allow_pki` because the PKI demo lives there.
  - `vault-secrets-webhook` — bound to the webhook's own SA in the `vault` namespace; used when the webhook resolves cross-namespace ConfigMap/Secret refs with its own identity.
- **Secrets engines**: KV v2 at `secret/`, PKI at `pki/` (self-signed root `CN=vault.default`, role `default` allowing `pod,svc,default` subdomains).
- **startupSecrets**: dev-only seeds at `secret/accounts/aws`, `secret/dockerrepo`, `secret/mysql`, `secret/payment`, `secret/smtp` — consumed by the Hipster demo patterns.

### Runtime config highlights

- `config.disable_mlock: true` — required under Raft (Raft mmaps log files; mlock on them OOMs the pod).
- `serviceType: ClusterIP` + Traefik Ingress on `vault.local`.
- 3-replica Raft HA; each pod gets its own PVC `vault-raft-*` backed by the shared `gp3` StorageClass from the `storage-classes` ApplicationSet.

### Drift handling (ApplicationSet `ignoreDifferences`)

The webhook chart regenerates its self-signed serving cert on every Helm render. To stop selfHeal from fighting it, the ApplicationSet ignores:
- `MutatingWebhookConfiguration` `.webhooks[].clientConfig.caBundle`
- `Secret/vault-secrets-webhook-webhook-tls` `/data`
- `Deployment/vault-secrets-webhook` pod-template `checksum/secret` + `checksum/config` annotations

and sets `syncOptions: [ServerSideApply=true, RespectIgnoreDifferences=true]`. Without `RespectIgnoreDifferences` selfHeal would still push fresh certs each sync.

### Non-production caveats

- Unseal keys + root token are stored as K8s Secret `vault-unseal-keys` in the `vault` namespace — sandbox shortcut; production would use KMS-backed autounseal.
- `startupSecrets` ships dev credentials in Git — demo only.
- `gp3` has `reclaimPolicy: Delete`, so deleting the Vault CR drops the Raft PVCs and loses all KV data.

### Consumer side

Hipster is the live reference for how to consume this plane. Patterns 1–4 work through `vault-env` at pod runtime; pattern 5 (PKI-to-disk) needs both the `vault-ct-configmap` annotation and `vault-agent: "true"` annotation — the former points at the consul-template config, the latter makes the webhook inject a `vault-agent` sidecar that handles k8s login and writes a token file that consul-template reads via `vault_agent_token_file`. See [argocd/manifests/hipster/adservice.yaml](argocd/manifests/hipster/adservice.yaml) + README "Hipster demo app" section.

## Root Application

A single `Application` CR (`root`) deployed by Terraform via `kubectl_manifest` points at `argocd/applications/` with `directory.recurse: true`. It materialises every `ApplicationSet` under `core/` and `apps/`, which in turn create the actual child Applications per cluster.

## Provider auth

All Kubernetes-scoped providers (`helm`, `kubectl`, `kubernetes`) authenticate via `exec` calling `aws eks get-token --cluster-name <module.eks.cluster_name>`. Do not replace this with a static `data.aws_eks_cluster_auth.cluster.token` — that token has a ~15-minute TTL and expires mid-apply on long runs; `exec` refreshes on each provider call.

## Bootstrap gap

There is a 60–90 second window after `terraform apply` completes when the ArgoCD UI is not yet reachable via `argocd.local` — Traefik hasn't synced yet. Use `kubectl -n argocd port-forward svc/argocd-server 8080:80` once, then switch to the ingress hostname once Traefik is up. After that, all platform + app changes happen via `git push`, not `terraform apply`.

## Common commands

```bash
# Bootstrap / day-2 cluster-layer changes
cd terraform
terraform init -upgrade
terraform plan
terraform apply

# Inspect GitOps state
kubectl -n argocd get applications
kubectl -n argocd get applicationsets
kubectl -n argocd get secret in-cluster -o yaml | grep -A20 annotations

# Force ArgoCD to re-sync (useful during migration)
kubectl -n argocd patch application root --type merge \
  -p '{"operation":{"sync":{}}}'
```

State is local (`terraform.tfstate` in the working directory, gitignored via `*.tfstate*`) — this is a sandbox project, not production-ready.
