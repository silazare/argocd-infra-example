---
replicaCount: 2

serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: ${alb_ingress_controller_role_arn}

rbac:
  create: true

clusterName: ${cluster_name}

region: ${aws_region}

vpcId: ${vpc_id}
