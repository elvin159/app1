data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_subject]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  for_each = toset(local.apps)

  name                 = "github-app1-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.github_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "ecr" {
  for_each = toset(local.apps)

  statement {
    sid       = "Login"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushAndPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app[each.key].arn]
  }

  # Promotion: read the same image from the previous environment's registry.
  dynamic "statement" {
    for_each = local.promotion_source_account_id == null ? [] : [1]

    content {
      sid = "PromotionPull"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:DescribeImages",
        "ecr:GetDownloadUrlForLayer",
      ]
      resources = ["arn:aws:ecr:${local.region}:${local.promotion_source_account_id}:repository/app1/${each.key}"]
    }
  }
}

resource "aws_iam_role_policy" "ecr" {
  for_each = toset(local.apps)

  name   = "ecr"
  role   = aws_iam_role.github_deploy[each.key].id
  policy = data.aws_iam_policy_document.ecr[each.key].json
}
