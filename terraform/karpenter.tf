resource "helm_release" "karpenter_crd" {
  name                = "karpenter-crd"
  chart               = "karpenter-crd"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  namespace           = "kube-system"
  version             = local.karpenter_version
  wait                = false

  timeout = 360

  lifecycle {
    ignore_changes = [
      repository_password
    ]
  }

  depends_on = [
    module.eks,
    module.karpenter
  ]
}

resource "helm_release" "karpenter" {
  name                = "karpenter"
  chart               = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  namespace           = "kube-system"
  version             = local.karpenter_version
  wait                = false

  values = [
    <<-EOT
    nodeSelector:
      karpenter.sh/controller: 'true'
    tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - key: karpenter.sh/controller
        operator: Exists
        effect: NoSchedule
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]

  timeout = 360

  lifecycle {
    ignore_changes = [
      repository_password
    ]
  }

  depends_on = [
    module.eks,
    module.karpenter,
    helm_release.karpenter_crd,
  ]
}

// Default EC2NodeClass and NodePool
resource "kubectl_manifest" "karpenter_ec2nodeclass_default" {
  yaml_body = <<EOF
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@latest # Amazon Linux 2023
  role: ${module.karpenter.node_iam_role_name}
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${local.name}
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${local.name}
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 64Gi
        volumeType: gp3
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 2
    httpTokens: required
  tags:
    karpenter.sh/discovery: ${local.name}
    CostCenter: ${local.name}
EOF

  depends_on = [
    helm_release.karpenter_crd,
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "karpenter_nodepool_default" {
  yaml_body = <<EOF
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  disruption:
    budgets:
      - nodes: 10%
    consolidateAfter: 0s
    consolidationPolicy: WhenEmptyOrUnderutilized
  limits:
    cpu: "100"
    memory: 100Gi
  template:
    metadata:
      labels:
        nodegroup: default
    spec:
      expireAfter: 720h
      # References the Cloud Provider's NodeClass resource
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["t"]
          minValues: 1
        - key: "karpenter.k8s.aws/instance-cpu"
          operator: In
          values: ["4", "8"]
        - key: "karpenter.k8s.aws/instance-generation"
          operator: Gt
          values: ["2"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot"]
EOF

  depends_on = [
    helm_release.karpenter_crd,
    helm_release.karpenter,
    kubectl_manifest.karpenter_ec2nodeclass_default
  ]
}
