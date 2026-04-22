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

argocd/applications/                      # GitOps — discovered recursively by the root Application
  core/
    traefik.yaml                  # ApplicationSet, reads traefik_sg_id from cluster Secret
    alb-controller.yaml           # ApplicationSet, reads role ARN + vpc_id + cluster_name
  apps/                           # Vault, Grafana, etc. — migrate here over time

argocd/helm-values/               # static Helm values referenced by Applications
  traefik/values.yaml
  alb-controller/values.yaml
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

ApplicationSets in `argocd/applications/core/` use a `clusters` generator that matches this Secret and expands `{{metadata.annotations.*}}` placeholders inline in the Helm values block. The static parts of values live in `argocd/helm-values/<app>/values.yaml`, pulled via a multi-source `$values` ref.

## Component relationships

- **VPC** → **EKS**: VPC id and private subnets. Traefik-specific SGs live in VPC so they're available for the cluster Secret.
- **EKS** → **Karpenter submodule**: cluster_name for IAM / SQS / EventBridge wiring.
- **EKS + Karpenter submodule** → **Karpenter Helm** (`karpenter.tf`): `queue_name` + `node_iam_role_name` as Helm values.
- **EKS** → **ALB controller Pod Identity** (`iam.tf`): standalone `aws_eks_pod_identity_association` for `aws-load-balancer-controller` SA in `kube-system`.
- **EKS** → **EBS CSI Pod Identity** (`eks.tf`): inline `pod_identity_association` inside the `aws-ebs-csi-driver` addon block, referencing `aws_iam_role.ebs_csi_controller` from `iam.tf`.
- Both Pod Identity roles share a single assume policy (`data.aws_iam_policy_document.pod_identity_assume` in `iam.tf`) trusting `pods.eks.amazonaws.com`.
- **ArgoCD Helm release** → **cluster Secret** → **ApplicationSets** → **Traefik / ALB charts**: the chain that lets Git manifests consume TF outputs.

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
