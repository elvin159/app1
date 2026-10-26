# Frontend static assets on S3 behind CloudFront (HTTPS). CloudFront is global, so there is one site
# per environment, not one per region.
module "bucket" {
  source = "git::https://github.com/elvin159/terraform-aws-bucket.git?ref=0d9d63ed5102dd424664ca0cc19d5a3ead310c92"

  name            = "app1-${local.environment}-static"
  domain_names    = [local.static_domain]
  hosted_zone_id  = local.hosted_zone_id
  single_page_app = false
  force_destroy   = local.force_destroy
}

resource "aws_iam_role_policy" "static_deploy" {
  name   = "static-assets-deploy"
  role   = aws_iam_role.github_deploy["frontend"].id
  policy = module.bucket.deploy_policy_json
}

# The frontend pipeline reads these instead of hardcoding names.
resource "aws_ssm_parameter" "static" {
  for_each = {
    bucket-name     = module.bucket.bucket_name
    distribution-id = module.bucket.distribution_id
  }

  name  = "/app1/static/${each.key}"
  type  = "String"
  value = each.value
}

data "aws_iam_policy_document" "read_static_parameters" {
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [for p in aws_ssm_parameter.static : p.arn]
  }
}

resource "aws_iam_role_policy" "read_static_parameters" {
  name   = "read-static-parameters"
  role   = aws_iam_role.github_deploy["frontend"].id
  policy = data.aws_iam_policy_document.read_static_parameters.json
}
