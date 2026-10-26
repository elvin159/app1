# Images are pushed once, to the primary region, and replicated to the account's other regions.
# Promotion copies an image from the previous environment's registry (see github.tf).

resource "aws_ecr_repository" "app" {
  for_each = toset(local.apps)

  name                 = "app1/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = local.force_destroy

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each = aws_ecr_repository.app

  repository = each.value.name
  policy     = local.ecr_lifecycle_policy
}

# Replication is configured once per registry. It creates the app1/* repositories in each replica
# region on first push, using the creation template below for their settings.
resource "aws_ecr_replication_configuration" "this" {
  for_each = length(local.replica_regions) > 0 ? { this = local.replica_regions } : {}

  replication_configuration {
    rule {
      dynamic "destination" {
        for_each = each.value

        content {
          region      = destination.value
          registry_id = local.account_id
        }
      }

      repository_filter {
        filter      = "app1/"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

resource "aws_ecr_repository_creation_template" "replica" {
  for_each = toset(local.replica_regions)

  region               = each.key
  prefix               = "app1"
  description          = "app1 repositories created by replication from ${local.region}"
  applied_for          = ["REPLICATION"]
  image_tag_mutability = "IMMUTABLE"
  lifecycle_policy     = local.ecr_lifecycle_policy

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# The next environment's deploy role may pull from these repositories to promote an image.
locals {
  promotion_pullers = {
    for app in(local.promotion_target_account_id == null ? [] : local.apps) : app => {
      account = "arn:aws:iam::${local.promotion_target_account_id}:root"
      role    = "arn:aws:iam::${local.promotion_target_account_id}:role/github-app1-${app}"
    }
  }
}

data "aws_iam_policy_document" "promotion_pull" {
  for_each = local.promotion_pullers

  statement {
    sid = "PromotionPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]

    principals {
      type        = "AWS"
      identifiers = [each.value.account]
    }

    # By ARN condition rather than principal, so the role doesn't have to exist yet.
    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = [each.value.role]
    }
  }
}

resource "aws_ecr_repository_policy" "promotion_pull" {
  for_each = data.aws_iam_policy_document.promotion_pull

  repository = aws_ecr_repository.app[each.key].name
  policy     = each.value.json
}
