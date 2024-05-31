# ArgoCD infra example

1) Deploy EKS cluster + Karpenter + ArgoCD with Terraform
2) Create ArgoCD applications
3) Retrieve ArgoCD admin password:
```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Bank-vaults
