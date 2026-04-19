################################################################################
# Common data/locals
################################################################################

data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name            = "ireland-test"
  cluster_version = "1.35"
  region          = "eu-west-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
    Owner      = "slazarev"
  }

  argocd_version                       = "9.5.2"
  aws_load_balancer_controller_version = "3.2.1"
  karpenter_version                    = "1.11.1"
  traefik_ingress_controller_version   = "39.0.8"
}
