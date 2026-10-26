# Terraform root for one stack. Identical in every environment and region: the environment and region
# come from the folder names, everything else from ../../env.yaml.
terraform {
  required_version = "1.17.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }
  }

  # CI passes the bucket (state_bucket in env.yaml) and the key (this folder's path).
  backend "s3" {
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

locals {
  environment = basename(abspath("${path.module}/../.."))
  region      = basename(abspath("${path.module}/.."))
  config      = yamldecode(file("${path.module}/../../env.yaml"))
}

# OIDC only: CI assumes a role in this account. allowed_account_ids stops a run against the wrong account.
provider "aws" {
  region              = local.region
  allowed_account_ids = [local.config.account_id]

  default_tags {
    tags = {
      Application = "app1"
      Environment = local.environment
      ManagedBy   = "terraform"
    }
  }
}

# Short-lived token from the CI role's AWS session; no kubeconfig or static credentials.
provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.this.name, "--region", local.region]
    }
  }
}

data "aws_eks_cluster" "this" {
  name = local.config.regions[local.region].cluster_name
}

module "platform" {
  source      = "../../../stacks/platform"
  environment = local.environment
  region      = local.region
  config      = local.config
}

output "platform" {
  description = "Outputs of stacks/platform."
  value       = module.platform
}
