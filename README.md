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

## Bank-vaults (demo example with local vault file unsealer)

Also inspired by this (demo)[https://github.com/sagikazarmark/demo-bank-vaults/tree/main]

1) Create Vault application:
```
k apply -f bank-vaults/application.yaml
```

2) Wait until Vault will be synced

3) Login to Vault UI and retreive root token:
```
k -n vault get secret vault-unseal-keys -o jsonpath="{.data.vault-root}" | base64 -d
```

4) Login to Vault CLI after port-forward:
```
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_SKIP_VERIFY=true
vault status

export VAULT_TOKEN="xxxxx"
vault kv get secret/mysql
```

5) Deploy demo application and check webhook logs and application POD:
```
k apply -f demo-app/.
```

6) You can retreive secrets inside the container via command: `/vault/vault-env env`

## TODO Roadmap

- Nginx Ingress Controller
- Bookinfo application
- Prometheus operator
- EFK
- Tracing
