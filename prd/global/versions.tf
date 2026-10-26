terraform {
  required_version = "1.17.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
  }

  # State lives in this environment's account, created during account bootstrap.
  backend "s3" {
    bucket       = "app1-terraform-state-333333333333"
    key          = "app1/global/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
