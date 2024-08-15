# Infra Components
- Karpenter - EC2 nodes management
- ArgoCD - GitOps
- Hashicorp Vault + Bank Vaults Operator - Secrets management
- Nginx Ingress Controller - Ingress
- Loki + Promtail - Logging
- Banzai Logging operator - Logging
- Kube-Prometheus-Stack - Metrics
- Trivy Operator - Security
- Kyverno - Security

## ArgoCD deploy

1) Deploy EKS cluster + Karpenter + ArgoCD with Terraform
2) Map local domains in `/etc/hosts` with NLB IP address:
  - argocd.local
  - vault.local
  - hipster.local

3) Retrieve ArgoCD admin password:
```
k -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

4) Login to cli and init repos:
```
argocd login argocd.local:443

argocd repo add https://github.com/silazare/argocd-infra-example.git --username silazare --password github_pat_xxxxx

argocd repo add ghcr.io --type helm --name stable --enable-oci
```

## Bank-vaults deploy (demo example with local vault file unsealer)

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

4) Login to Vault CLI:
```
export VAULT_ADDR=http://vault.local
export VAULT_SKIP_VERIFY=true
vault status

export VAULT_TOKEN="xxxxx"
vault kv get secret/mysql
vault kv get secret/accounts/aws
```

5) Deploy demo application and check webhook logs and application POD:
```
k apply -f demo-app/.
```

6) You can retreive secrets inside the container via command: `/vault/vault-env env`

## Hipster demo app deploy (without Istio)

1) Create Vault application:
```
k apply -f hipster-app/application.yaml
```

2) Wait until app will be synced

3) Login to Frontend UI and make sure app is working fine:
```
http://hipster.local/
```
