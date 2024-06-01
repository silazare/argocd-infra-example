# ArgoCD infra example

1) Deploy EKS cluster + Karpenter + ArgoCD with Terraform
2) Create ArgoCD applications
3) Retrieve ArgoCD admin password:
```
k -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
4) Login to cli and init repos:
```
argocd login localhost:8080

argocd repo add https://github.com/silazare/argocd-infra-example.git --username silazare --password github_pat_xxxxx

argocd repo add ghcr.io --type helm --name stable --enable-oci
```

## Bank-vaults

1) Create Vault application (best option):
```
k apply -f bank-vaults/application.yaml
```

Or ArgoCD cli option:
```
argocd app create vault --repo https://github.com/silazare/argocd-infra-example.git --path bank-vaults --dest-server https://kubernetes.default.svc --dest-namespace vault

argocd app sync vault
```

2) Wait until Vault will be synced

3) Login to Vault UI and retreive root token:
```
kubectl get secret -n default vault-unseal-keys -o jsonpath="{.data.vault-root}" | base64 -d
```

4) Login to Vault CLI after port-forward:
```
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_SKIP_VERIFY=true
vault status
```
