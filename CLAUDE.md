# Project Overview

AWS EKS cluster bootstrap with ArgoCD for GitOps, deployed via Terraform. The Terraform layer provisions the VPC, EKS cluster, Karpenter, AWS Load Balancer Controller, Traefik ingress and ArgoCD. Application layer (Vault, kube-prometheus-stack, Loki, Hipster demo) is managed by ArgoCD from this repo.

## Terraform Layer

Single flat stack under `terraform/`. No custom modules — the stack consumes public upstream modules directly:

- `terraform-aws-modules/vpc/aws` — VPC, subnets, NAT
- `terraform-aws-modules/eks/aws` — EKS cluster, addons, managed node group
- `terraform-aws-modules/eks/aws//modules/karpenter` — Karpenter controller IAM, SQS, EventBridge wiring

Everything else (Karpenter Helm, ALB controller, Traefik, ArgoCD) is a direct `helm_release` / `kubectl_manifest` resource.

### File map

| File | Purpose |
|---|---|
| `main.tf` | Locals (cluster name, region, chart versions), shared data sources |
| `versions.tf` | Terraform & provider version pins |
| `providers.tf` | `aws`, `helm`, `kubectl`, `kubernetes` providers (EKS-scoped ones use `exec` auth via `aws eks get-token`) |
| `vpc.tf` | VPC module + `ingress_traefik_external` / `ingress_traefik_node` security groups |
| `eks.tf` | `module "eks"` + `module "karpenter"` submodule |
| `karpenter.tf` | Karpenter Helm releases (CRD + controller) and default `EC2NodeClass` / `NodePool` manifests |
| `alb.tf` | AWS Load Balancer Controller IAM + Helm release |
| `traefik.tf` | Traefik Helm release (default IngressClass, NLB-backed service) |
| `argocd.tf` | ArgoCD Helm release + `Ingress` for `argocd.local` |

### Component relationships

- **VPC** (`vpc.tf`) → **EKS** (`eks.tf`): EKS consumes `module.vpc.vpc_id` and private subnets. Traefik-specific SGs live here so they're available to the Traefik service annotation.
- **EKS** → **Karpenter submodule** (`eks.tf`): Karpenter submodule needs `module.eks.cluster_name` to wire up its SQS/EventBridge.
- **EKS + Karpenter submodule** → **Karpenter Helm** (`karpenter.tf`): Helm release references `module.karpenter.queue_name` and `module.karpenter.node_iam_role_name`. The permanent managed node group (`eks_managed_node_groups.karpenter`) is tainted so only the Karpenter controller runs there; everything else lands on Karpenter-provisioned spot nodes.
- **EKS** → **ALB controller** (`alb.tf`): IAM role uses `module.eks.oidc_provider_arn`.
- **ALB controller** → **Traefik** (`traefik.tf`): Traefik service uses NLB annotations and the `ingress_traefik_external` SG. Traefik's default `IngressClass` makes it the cluster-wide ingress entrypoint.
- **Traefik** → **ArgoCD** (`argocd.tf`): Argo runs with `server.insecure: true` (TLS terminates on Traefik); its `Ingress` uses `ingressClassName: traefik`.

### Provider auth

All Kubernetes-scoped providers (`helm`, `kubectl`, `kubernetes`) authenticate via `exec` calling `aws eks get-token --cluster-name <module.eks.cluster_name>`. Do not replace this with `data.aws_eks_cluster_auth.cluster.token` — the static token expires mid-apply on long runs; `exec` refreshes on each provider call.

## Common Commands

```bash
cd terraform

terraform init -upgrade
terraform plan
terraform apply
```

State is local (`terraform.tfstate` committed in the directory) and this is a Sandbox project, not production ready.
