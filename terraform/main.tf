################################################################################
# Common data/locals
################################################################################

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

data "aws_availability_zones" "available" {}

locals {
  name            = "ireland-test-cluster"
  cluster_version = "1.30"
  region          = "eu-west-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
    Owner      = "slazarev"
  }

  argocd_version                       = "6.11.1"
  aws_load_balancer_controller_version = "1.8.1"
  karpenter_version                    = "0.37.0"
  nginx_ingress_controller_version     = "4.10.1"
}
