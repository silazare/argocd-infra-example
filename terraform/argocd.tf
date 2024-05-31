resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  version          = "6.11.1"
  create_namespace = true

  depends_on = [
    module.eks,
    helm_release.karpenter
  ]
}
