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

resource "kubernetes_manifest" "argocd_ingress" {
  manifest = {
    "apiVersion" = "networking.k8s.io/v1"
    "kind"       = "Ingress"
    "metadata" = {
      "annotations" = {
        "alb.ingress.kubernetes.io/ssl-passthrough"      = "true"
        "nginx.ingress.kubernetes.io/backend-protocol"   = "HTTPS"
        "nginx.ingress.kubernetes.io/force-ssl-redirect" = "false"
      }
      "name"      = "argocd-server-ingress"
      "namespace" = "argocd"
    }
    "spec" = {
      "ingressClassName" = "nginx"
      "rules" = [
        {
          "host" = "argocd.local"
          "http" = {
            "paths" = [
              {
                "backend" = {
                  "service" = {
                    "name" = "argocd-server"
                    "port" = {
                      "number" = 443
                    }
                  }
                }
                "path"     = "/"
                "pathType" = "Prefix"
              },
            ]
          }
        },
      ]
    }
  }

  depends_on = [
    module.eks,
    helm_release.argocd
  ]
}
