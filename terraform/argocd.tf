resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  version          = local.argocd_version
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

resource "kubectl_manifest" "argocd_ingress" {
  yaml_body = <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    alb.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.local
    http:
      paths:
      - pathType: Prefix
        path: /
        backend:
          service:
            name: argocd-server
            port:
              number: 443
EOF

  depends_on = [
    helm_release.argocd,
    helm_release.nginx_ingress_controller
  ]
}
