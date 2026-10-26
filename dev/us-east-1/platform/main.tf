locals {
  environment          = "dev"
  account_id           = "111111111111"
  region               = "us-east-1"
  cluster_name         = "app1-dev-use1"
  primary_region       = "us-east-1"
  primary_cluster_name = "app1-dev-use1"
  is_primary           = local.region == local.primary_region
  apps                 = ["backend", "frontend"]

  # Bootstrap prerequisites (stub values).
  domain               = "dev.example.com"
  hosted_zone_id       = "Z0000000000000000DEV"
  repo_ssh_url         = "git@github.com:elvin159/app1.git"
  repo_ssh_secret_name = "app1/argocd-repo-ssh-key"
}

# OIDC only: CI assumes a role in this account. allowed_account_ids stops a run against the wrong account.
provider "aws" {
  region              = local.region
  allowed_account_ids = [local.account_id]

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
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.region]
    }
  }
}

data "aws_eks_cluster" "this" {
  name = local.cluster_name
}

# IRSA roles from the identity stack.
data "aws_iam_role" "irsa" {
  for_each = toset(["aws-load-balancer-controller", "external-dns", "external-secrets", "cluster-autoscaler"])

  name = "${local.cluster_name}-${each.key}"
}

# The writer holds the database name and the master secret.
data "aws_db_instance" "primary" {
  region                 = local.primary_region
  db_instance_identifier = local.primary_cluster_name
}

# The local instance each app connects to: the backend reads from a read replica; the frontend uses
# the writer where it is local, and this region's replica elsewhere.
data "aws_db_instance" "app" {
  for_each = {
    backend  = local.is_primary ? "${local.cluster_name}-read1" : local.cluster_name
    frontend = local.cluster_name
  }

  db_instance_identifier = each.value
}
