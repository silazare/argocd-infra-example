resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  version          = "6.11.1"
  create_namespace = true

  values = [
    <<-EOT
    redis-ha:
      enabled: true
    controller:
      replicas: 1
    server:
      autoscaling:
        enabled: true
        minReplicas: 2
    repoServer:
      autoscaling:
        enabled: true
        minReplicas: 2
    applicationSet:
      replicas: 2
    EOT
  ]

  depends_on = [
    module.eks,
    helm_release.karpenter
  ]
}
