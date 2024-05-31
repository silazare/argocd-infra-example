provider "aws" {
  alias  = "north"
  region = "eu-north-1"
}

provider "aws" {
  alias  = "asia"
  region = "ap-southeast-1"
}

provider "kubernetes" {
  alias                  = "north"
  host                   = module.eks_north.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_north.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks_north.cluster_name]
  }
}

provider "kubernetes" {
  alias                  = "asia"
  host                   = module.eks_asia.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_asia.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks_asia.cluster_name]
  }
}


provider "helm" {
  alias = "north"
  kubernetes {
    host                   = module.eks_north.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_north.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks_north.cluster_name]
    }
  }
}

provider "helm" {
  alias = "asia"
  kubernetes {
    host                   = module.eks_asia.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_asia.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks_asia.cluster_name]
    }
  }
}

provider "kubectl" {
  alias                  = "north"
  apply_retry_count      = 5
  host                   = module.eks_north.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_north.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks_north.cluster_name]
  }
}

provider "kubectl" {
  alias                  = "asia"
  apply_retry_count      = 5
  host                   = module.eks_asia.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_asia.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks_asia.cluster_name]
  }
}
