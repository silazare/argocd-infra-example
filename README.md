# ArgoCD infra example

1) Deploy EKS cluster + Karpenter + ArgoCD with Terraform
2) Create ArgoCD applications
3) Retrieve ArgoCD admin password:
```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
4) Login to cli and init repos:
```shell
argocd login localhost:8080

argocd repo add https://github.com/silazare/argocd-infra-example.git --username silazare --password github_pat_xxxxx

argocd repo add ghcr.io --type helm --name stable --enable-oci
```

### Bank-vaults

1) Create Vault application:
```
argocd app create vault --repo https://github.com/silazare/argocd-infra-example.git --path bank-vaults --dest-server https://kubernetes.default.svc --dest-namespace vault

argocd app sync vault
```
