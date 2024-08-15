## Vault Operator

Important considerations:

- This setup is non-production, becase unseal keys are stored in the same cluster and k8s secrets, consider KMS
- The unseal keys and root token are managed by the Bank-Vaults operator.
- There are 5 key shares created, with a threshold of 3 required to unseal Vault.
- The unseal information is stored as Kubernetes Secrets in the "vault" namespace.
- The secrets managed by Vault are stored in the Raft storage, which is persisted on the Kubernetes PersistentVolumes.
- Each Vault pod will have its own PersistentVolume, and Raft ensures that the data is replicated across these volumes for high availability.

## Archive manifests for historical purposes

1) `vault-cr-file.yaml` - Single Vault node with file storage on PVC (HA not possible)
